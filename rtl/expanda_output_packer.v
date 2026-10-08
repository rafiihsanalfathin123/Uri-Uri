`timescale 1ns/1ps
// Continuous 23-bit bitstream: 256*23 = 46*128 bits, no padding.
module expanda_output_packer (
    input wire clk, rst, packer_start,
    input wire [3:0] poly_idx,
    input wire [22:0] coeff_data,
    input wire [7:0] coeff_idx,
    input wire coeff_valid,
    output wire coeff_ready,
    output wire [127:0] sampled_poly_data,
    output wire sampled_poly_valid,
    input wire sampled_poly_ready,
    output reg [3:0] sampled_poly_idx,
    output reg [5:0] sampled_word_idx,
    output wire sampled_poly_last,
    output reg packer_poly_done, packer_error
);
    reg [149:0] reservoir;
    reg [7:0] bit_count;
    reg [8:0] coeff_count;
    reg active;
    wire pop = sampled_poly_valid && sampled_poly_ready;
    wire push = coeff_valid && coeff_ready;
    wire [7:0] append_offset = pop ? bit_count - 8'd128 : bit_count;
    wire [149:0] remaining = pop ? reservoir >> 128 : reservoir;
    assign sampled_poly_valid = active && bit_count >= 128 && !rst && !packer_error;
    assign sampled_poly_data = reservoir[127:0];
    assign sampled_poly_last = sampled_word_idx == 45;
    assign coeff_ready = active && coeff_count < 256 &&
                         (bit_count < 128 || sampled_poly_ready) && !rst && !packer_error;
    always @(posedge clk) begin
        if (rst) begin
            reservoir <= 0; bit_count <= 0; coeff_count <= 0; active <= 0;
            sampled_poly_idx <= 0; sampled_word_idx <= 0; packer_poly_done <= 0; packer_error <= 0;
        end else begin
            packer_poly_done <= 0;
            if (packer_start) begin
                reservoir <= 0; bit_count <= 0; coeff_count <= 0;
                active <= 1; sampled_poly_idx <= poly_idx; sampled_word_idx <= 0;
            end else begin
                if (push) begin
                    if (coeff_idx != coeff_count[7:0]) packer_error <= 1;
                    reservoir <= remaining | ({{127{1'b0}},coeff_data} << append_offset);
                    bit_count <= append_offset + 8'd23;
                    coeff_count <= coeff_count + 1'b1;
                end else if (pop) begin reservoir <= remaining; bit_count <= append_offset; end
                if (pop) begin
                    if (sampled_poly_last) begin active <= 0; packer_poly_done <= 1; end
                    else sampled_word_idx <= sampled_word_idx + 1'b1;
                end
            end
        end
    end
endmodule
