`timescale 1ns/1ps
// Lossless single-word elastic serializer. First-byte position is explicit.
module expanda_word_to_byte #(parameter MSB_FIRST = 1, parameter WORD_BITS = 64) (
    input wire clk, rst, flush,
    input wire [WORD_BITS-1:0] word_data,
    input wire word_valid,
    output wire word_ready,
    output wire [7:0] byte_data,
    output wire byte_valid,
    input wire byte_ready
);
    localparam WORD_BYTES = WORD_BITS / 8;
    function integer index_width;
        input integer value;
        integer count;
        begin
            value = value - 1;
            for (count = 0; value > 0; count = count + 1) value = value >> 1;
            index_width = count;
        end
    endfunction
    localparam INDEX_BITS = index_width(WORD_BYTES);
    reg [WORD_BITS-1:0] held_word;
    reg [INDEX_BITS-1:0] index;
    reg occupied;
    assign word_ready = !occupied && !flush && !rst;
    assign byte_valid = occupied && !flush && !rst;
    assign byte_data = MSB_FIRST ? held_word[WORD_BITS-1-index*8 -: 8] : held_word[index*8 +: 8];
    always @(posedge clk) begin
        if (rst || flush) begin held_word <= 0; index <= 0; occupied <= 0; end
        else begin
            if (word_valid && word_ready) begin held_word <= word_data; index <= 0; occupied <= 1; end
            if (byte_valid && byte_ready) begin
                if (index == WORD_BYTES-1) begin occupied <= 0; index <= 0; end
                else index <= index + 1'b1;
            end
        end
    end
endmodule
