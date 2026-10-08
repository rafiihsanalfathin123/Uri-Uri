// ExpandA-44 after SHAKE128. Sequential producer; bounded, reusable row storage.
`timescale 1ns/1ps
module expanda_stream_top (
    input wire clk, rst,
    input wire job_valid,
    output wire job_ready,
    input wire [255:0] rho,
    output wire xof_request_valid,
    input wire xof_request_ready,
    output reg [255:0] xof_rho,
    output reg [1:0] xof_row, xof_col,
    input wire [7:0] xof_byte_data,
    input wire xof_byte_valid,
    output wire xof_byte_ready,
    output wire xof_cancel,
    output wire row_valid,
    output wire [1:0] row_index,
    input wire row_release,
    input wire row_read_enable,
    input wire [7:0] row_read_addr,
    output wire [95:0] row_read_data,
    output wire row_read_valid,
    output wire busy,
    output reg job_done
);
    localparam IDLE=0, REQUEST=1, FILL=2, PUBLISH=3;
    reg [1:0] state;
    reg [1:0] lane;
    reg [5:0] word_index;
    reg [95:0] packed_word;
    wire [22:0] coeff;
    wire coeff_valid, coeff_last, sampler_done, sampler_busy;
    wire sampler_byte_ready;
    wire start_poly = xof_request_valid && xof_request_ready;
    wire coeff_ready = (state == FILL);
    wire write_word = coeff_valid && coeff_ready && (lane == 3);
    wire [95:0] completed_word = {1'b0, coeff, packed_word[71:0]};
    assign job_ready = (state == IDLE) && !rst;
    assign busy = (state != IDLE);
    assign xof_request_valid = (state == REQUEST) && !rst;
    assign xof_byte_ready = (state == FILL) && sampler_byte_ready && !rst;
    assign xof_cancel = sampler_done;
    assign row_valid = (state == PUBLISH) && !rst;
    assign row_index = xof_row;
    expanda_rejection_sampler sampler (
        .clk(clk), .rst(rst), .start(start_poly),
        .byte_data(xof_byte_data), .byte_valid(xof_byte_valid && state == FILL),
        .byte_ready(sampler_byte_ready), .coeff_data(coeff),
        .coeff_valid(coeff_valid), .coeff_ready(coeff_ready),
        .coeff_last(coeff_last), .busy(sampler_busy), .done(sampler_done)
    );
    expanda_row_buffer buffer (
        .clk(clk), .rst(rst), .write_enable(write_word),
        .write_addr({xof_col, word_index}), .write_data(completed_word),
        .read_enable(row_read_enable && row_valid && !row_release),
        .read_addr(row_read_addr), .read_data(row_read_data), .read_valid(row_read_valid)
    );
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; xof_rho <= 0; xof_row <= 0; xof_col <= 0;
            lane <= 0; word_index <= 0; packed_word <= 0; job_done <= 0;
        end else begin
            job_done <= 0;
            case (state)
                IDLE: if (job_valid && job_ready) begin
                    xof_rho <= rho; xof_row <= 0; xof_col <= 0; state <= REQUEST;
                end
                REQUEST: if (start_poly) begin
                    lane <= 0; word_index <= 0; packed_word <= 0; state <= FILL;
                end
                FILL: begin
                    if (coeff_valid && coeff_ready) begin
                        packed_word[lane*24 +: 24] <= {1'b0, coeff};
                        lane <= lane + 1'b1;
                        if (lane == 3) word_index <= word_index + 1'b1;
                    end
                    if (sampler_done) begin
                        if (xof_col == 3) state <= PUBLISH;
                        else begin xof_col <= xof_col + 1'b1; state <= REQUEST; end
                    end
                end
                PUBLISH: if (row_release) begin
                    // Consumer must drain outstanding reads/operand uses first.
                    if (xof_row == 3) begin state <= IDLE; job_done <= 1; end
                    else begin xof_row <= xof_row + 1'b1; xof_col <= 0; state <= REQUEST; end
                end
            endcase
        end
    end
endmodule
