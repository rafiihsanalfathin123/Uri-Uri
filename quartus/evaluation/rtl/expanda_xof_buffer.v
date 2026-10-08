`timescale 1ns/1ps
// At most two leftover bytes plus a new 16-byte word: 18 bytes total.
module expanda_xof_buffer (
    input wire clk, rst, flush,
    input wire [127:0] shake_out_data,
    input wire shake_out_valid,
    output wire shake_out_ready,
    output wire [23:0] sample_data,
    output wire sample_valid,
    input wire sample_req
);
    reg [143:0] reservoir;
    reg [4:0] byte_count;
    assign shake_out_ready = !rst && !flush && byte_count < 3;
    assign sample_valid = !rst && !flush && byte_count >= 3;
    assign sample_data = reservoir[23:0];
    always @(posedge clk) begin
        if (rst || flush) begin reservoir <= 0; byte_count <= 0; end
        else if (shake_out_valid && shake_out_ready) begin
            case (byte_count)
                0: reservoir <= {16'd0,shake_out_data};
                1: reservoir <= {8'd0,shake_out_data,reservoir[7:0]};
                2: reservoir <= {shake_out_data,reservoir[15:0]};
                default: reservoir <= 0;
            endcase
            byte_count <= byte_count + 5'd16;
        end else if (sample_valid && sample_req) begin
            reservoir <= reservoir >> 24;
            byte_count <= byte_count - 5'd3;
        end
    end
endmodule
