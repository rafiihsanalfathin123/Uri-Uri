`timescale 1ns/1ps
// Interface for an internal SHAKE128 producing complete 64-bit XOF words.
// MSB_FIRST=1 matches OSH sampler_a_ext's interpretation of Keccak dout.
module expanda_shake64_top #(parameter MSB_FIRST = 1) (
    input wire clk, rst,
    input wire job_valid,
    output wire job_ready,
    input wire [255:0] rho,
    output wire xof_request_valid,
    input wire xof_request_ready,
    output wire [255:0] xof_rho,
    output wire [1:0] xof_row, xof_col,
    input wire [63:0] shake_word_data,
    input wire shake_word_valid,
    output wire shake_word_ready,
    output wire osh_dst_ready,
    output wire xof_cancel,
    output wire row_valid,
    output wire [1:0] row_index,
    input wire row_release,
    input wire row_read_enable,
    input wire [7:0] row_read_addr,
    output wire [95:0] row_read_data,
    output wire row_read_valid,
    output wire busy,
    output wire job_done
);
    wire [7:0] byte_data;
    wire byte_valid, byte_ready, adapter_ready;
    // Admit words only in a sampling context. row hold/request/idle take none.
    assign shake_word_ready = adapter_ready && byte_ready;
    // OSH sha3_fsm3 writes when dst_ready=0 (inverse of conventional ready).
    assign osh_dst_ready = !shake_word_ready;
    expanda_word_to_byte #(.MSB_FIRST(MSB_FIRST)) serializer (
        .clk(clk), .rst(rst), .flush(xof_cancel), .word_data(shake_word_data),
        .word_valid(shake_word_valid && byte_ready), .word_ready(adapter_ready),
        .byte_data(byte_data), .byte_valid(byte_valid), .byte_ready(byte_ready)
    );
    expanda_stream_top core (
        .clk(clk), .rst(rst), .job_valid(job_valid), .job_ready(job_ready), .rho(rho),
        .xof_request_valid(xof_request_valid), .xof_request_ready(xof_request_ready),
        .xof_rho(xof_rho), .xof_row(xof_row), .xof_col(xof_col),
        .xof_byte_data(byte_data), .xof_byte_valid(byte_valid), .xof_byte_ready(byte_ready),
        .xof_cancel(xof_cancel), .row_valid(row_valid), .row_index(row_index),
        .row_release(row_release), .row_read_enable(row_read_enable), .row_read_addr(row_read_addr),
        .row_read_data(row_read_data), .row_read_valid(row_read_valid), .busy(busy), .job_done(job_done)
    );
endmodule
