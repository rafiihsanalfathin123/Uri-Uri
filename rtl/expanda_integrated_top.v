`timescale 1ns/1ps
// Complete ExpandA-44 generator: supplied shared SHAKE128 + bounded row storage.
// rho byte 0 is rho[7:0]; output word slots contain canonical 24-bit residues.
module expanda_integrated_top (
    input wire clk, rst,
    input wire job_valid,
    output wire job_ready,
    input wire [255:0] rho,
    output wire row_valid,
    output wire [1:0] row_index,
    input wire row_release,
    input wire row_read_enable,
    input wire [7:0] row_read_addr,
    output wire [95:0] row_read_data,
    output wire row_read_valid,
    output wire busy,
    output wire job_done,
    output reg job_error
);
    localparam CTRL_IDLE=0, CTRL_INIT=1, CTRL_ABSORB=2,
               CTRL_FINALIZE=3, CTRL_WAIT_FINAL=4, CTRL_SQUEEZE=5;
    reg [2:0] ctrl_state;
    reg [1:0] input_word;
    wire req_valid, req_ready, cancel;
    wire [255:0] req_rho;
    wire [1:0] req_row, req_col;
    wire [7:0] byte_data;
    wire byte_valid, byte_ready, adapter_ready;
    wire [127:0] shake_out_data;
    reg [127:0] shake_in_data;
    wire shake_in_ready, shake_out_valid, shake_ready, shake_phase_done, shake_error;
    wire core_job_ready, core_row_valid, core_read_valid, core_busy, core_done;
    wire internal_rst = rst || job_error || shake_error;
    wire shake_init = !internal_rst && ((ctrl_state == CTRL_INIT) || cancel);
    wire shake_absorb_en = (ctrl_state == CTRL_ABSORB);
    wire shake_finalize = (ctrl_state == CTRL_FINALIZE) && !internal_rst;
    wire shake_squeeze_en = (ctrl_state == CTRL_SQUEEZE) && !cancel && !internal_rst;
    wire shake_in_valid = shake_absorb_en && !internal_rst;
    wire [4:0] shake_in_nbytes = (input_word == 2) ? 5'd2 : 5'd16;
    wire shake_out_ready = adapter_ready && byte_ready && shake_squeeze_en;
    assign req_ready = (ctrl_state == CTRL_IDLE) && !internal_rst;
    assign job_ready = core_job_ready && !internal_rst;
    assign row_valid = core_row_valid && !internal_rst;
    assign row_read_valid = core_read_valid && !internal_rst;
    assign busy = core_busy && !internal_rst;
    assign job_done = core_done && !internal_rst;

    always @(*) begin
        case (input_word)
            0: shake_in_data = req_rho[127:0];
            1: shake_in_data = req_rho[255:128];
            default: shake_in_data = {112'd0, 6'd0, req_row, 6'd0, req_col};
        endcase
    end
    always @(posedge clk) begin
        if (rst) job_error <= 0;
        else if (shake_error) job_error <= 1; // sticky; explicit reset recovers
        if (internal_rst) begin ctrl_state <= CTRL_IDLE; input_word <= 0; end
        else if (cancel) begin ctrl_state <= CTRL_IDLE; input_word <= 0; end
        else case (ctrl_state)
            CTRL_IDLE: if (req_valid && req_ready) begin ctrl_state <= CTRL_INIT; input_word <= 0; end
            CTRL_INIT: ctrl_state <= CTRL_ABSORB;
            CTRL_ABSORB: if (shake_in_valid && shake_in_ready) begin
                if (input_word == 2) ctrl_state <= CTRL_FINALIZE;
                else input_word <= input_word + 1'b1;
            end
            CTRL_FINALIZE: ctrl_state <= CTRL_WAIT_FINAL;
            CTRL_WAIT_FINAL: if (shake_phase_done) ctrl_state <= CTRL_SQUEEZE;
            CTRL_SQUEEZE: begin end // continue this XOF until 256 coefficients
            default: ctrl_state <= CTRL_IDLE;
        endcase
    end

    shared_shake128_mem shake (
        .clk(clk), .rst(internal_rst), .shake_init(shake_init),
        .shake_absorb_en(shake_absorb_en), .shake_finalize(shake_finalize),
        .shake_squeeze_en(shake_squeeze_en), .shake_in_data(shake_in_data),
        .shake_in_valid(shake_in_valid), .shake_in_nbytes(shake_in_nbytes),
        .shake_in_ready(shake_in_ready), .shake_out_data(shake_out_data),
        .shake_out_valid(shake_out_valid), .shake_out_ready(shake_out_ready),
        .shake_ready(shake_ready), .shake_phase_done(shake_phase_done), .shake_error(shake_error)
    );
    expanda_word_to_byte #(.WORD_BITS(128), .MSB_FIRST(0)) serializer (
        .clk(clk), .rst(internal_rst), .flush(cancel), .word_data(shake_out_data),
        .word_valid(shake_out_valid && byte_ready && shake_squeeze_en),
        .word_ready(adapter_ready), .byte_data(byte_data), .byte_valid(byte_valid), .byte_ready(byte_ready)
    );
    expanda_stream_top core (
        .clk(clk), .rst(internal_rst), .job_valid(job_valid && !internal_rst),
        .job_ready(core_job_ready), .rho(rho), .xof_request_valid(req_valid),
        .xof_request_ready(req_ready), .xof_rho(req_rho), .xof_row(req_row), .xof_col(req_col),
        .xof_byte_data(byte_data), .xof_byte_valid(byte_valid), .xof_byte_ready(byte_ready),
        .xof_cancel(cancel), .row_valid(core_row_valid), .row_index(row_index), .row_release(row_release),
        .row_read_enable(row_read_enable), .row_read_addr(row_read_addr),
        .row_read_data(row_read_data), .row_read_valid(core_read_valid), .busy(core_busy), .job_done(core_done)
    );
endmodule
