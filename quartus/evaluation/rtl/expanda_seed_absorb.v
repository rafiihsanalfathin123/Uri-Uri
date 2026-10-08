`timescale 1ns/1ps
// Two 128-bit seed beats; three absorb beats for rho || column || row.
module expanda_seed_absorb (
    input wire clk, rst, load_enable, seed_use, seed_absorb_start,
    input wire [127:0] rho_data,
    input wire rho_valid,
    output wire rho_ready,
    output reg rho_loaded,
    input wire [1:0] row_idx, col_idx,
    output wire [127:0] shake_in_data,
    output wire [4:0] shake_in_nbytes,
    output wire shake_in_valid,
    input wire shake_in_ready,
    output reg absorb_done
);
    reg [255:0] seed;
    reg half_loaded;
    reg [1:0] input_word;
    reg absorbing;
    assign rho_ready = load_enable && !rho_loaded && !rst;
    assign shake_in_valid = absorbing && !rst;
    assign shake_in_nbytes = (input_word == 2) ? 5'd2 : 5'd16;
    assign shake_in_data = input_word == 0 ? seed[127:0] :
                           input_word == 1 ? seed[255:128] :
                           {112'd0,6'd0,row_idx,6'd0,col_idx};
    always @(posedge clk) begin
        if (rst) begin
            seed <= 0; half_loaded <= 0; rho_loaded <= 0;
            input_word <= 0; absorbing <= 0; absorb_done <= 0;
        end else begin
            absorb_done <= 0;
            if (rho_valid && rho_ready) begin
                if (!half_loaded) begin seed[127:0] <= rho_data; half_loaded <= 1; end
                else begin seed[255:128] <= rho_data; rho_loaded <= 1; end
            end
            if (seed_use) begin half_loaded <= 0; rho_loaded <= 0; end
            if (seed_absorb_start) begin input_word <= 0; absorbing <= 1; end
            else if (shake_in_valid && shake_in_ready) begin
                if (input_word == 2) begin absorbing <= 0; absorb_done <= 1; end
                else input_word <= input_word + 1'b1;
            end
        end
    end
endmodule
