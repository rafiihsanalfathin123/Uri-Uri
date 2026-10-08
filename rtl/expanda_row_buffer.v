// Four polynomials, 64 words each, four zero-padded 24-bit coefficients/word.
`timescale 1ns/1ps
module expanda_row_buffer (
    input wire clk, rst,
    input wire write_enable,
    input wire [7:0] write_addr,
    input wire [95:0] write_data,
    input wire read_enable,
    input wire [7:0] read_addr,
    output reg [95:0] read_data,
    output reg read_valid
);
    reg [95:0] memory [0:255];
    // Contents need no reset: the controller publishes only fully written rows.
    always @(posedge clk) begin
        if (write_enable && !rst) memory[write_addr] <= write_data;
        // Keep the RAM read register unreset so Quartus can absorb it into
        // embedded RAM. read_valid invalidates old/undefined data on reset.
        if (read_enable) read_data <= memory[read_addr];
        if (rst) read_valid <= 0;
        else read_valid <= read_enable;
    end
endmodule
