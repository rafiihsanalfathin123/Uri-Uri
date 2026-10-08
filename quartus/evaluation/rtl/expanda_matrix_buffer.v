`timescale 1ns/1ps
// Same producer and packed format; ROWS=1 reusable row, ROWS=4 full matrix.
module expanda_matrix_buffer #(parameter ROWS = 1) (
    input wire clk, rst,
    input wire [127:0] stream_data,
    input wire stream_valid,
    output wire stream_ready,
    input wire [3:0] stream_poly_idx,
    input wire [5:0] stream_word_idx,
    input wire stream_last,
    output reg buffer_valid,
    output reg [1:0] buffer_first_row,
    input wire buffer_release,
    input wire read_enable,
    input wire [9:0] read_addr,
    output reg [127:0] read_data,
    output reg read_valid,
    output wire buffer_empty
);
    function integer address_width;
        input integer value;
        integer count;
        begin
            value = value-1;
            for(count=0;value>0;count=count+1) value=value>>1;
            address_width=count;
        end
    endfunction
    localparam DEPTH = ROWS*184;
    localparam ADDR_BITS = address_width(DEPTH);
    reg [127:0] memory [0:DEPTH-1];
    reg [ADDR_BITS-1:0] write_addr;
    wire read_request = read_enable && buffer_valid && !buffer_release && read_addr < DEPTH;
    assign stream_ready = !buffer_valid && !rst;
    assign buffer_empty = !buffer_valid && write_addr == 0;
    always @(posedge clk) begin
        // Unreset synchronous read data permits embedded RAM inference.
        if (read_request) read_data <= memory[read_addr[ADDR_BITS-1:0]];
        if (rst) begin write_addr <= 0; buffer_valid <= 0; buffer_first_row <= 0; read_valid <= 0; end
        else begin
            read_valid <= read_request;
            if (buffer_release) buffer_valid <= 0;
            if (stream_valid && stream_ready) begin
                memory[write_addr] <= stream_data;
                if (write_addr == 0) buffer_first_row <= stream_poly_idx[3:2];
                if (write_addr == DEPTH-1) begin write_addr <= 0; buffer_valid <= 1; end
                else write_addr <= write_addr + 1'b1;
            end
        end
    end
endmodule
