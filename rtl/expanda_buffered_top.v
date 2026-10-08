`timescale 1ns/1ps
module expanda_buffered_top #(parameter ROWS = 1, parameter PARALLEL_LANES = 5) (
    input wire clk, rst,
    input wire [127:0] rho_data,
    input wire rho_valid,
    output wire rho_ready, rho_loaded,
    input wire expand_a_start,
    output wire expand_a_ready, expand_a_busy, expand_a_done, expand_a_error,
    output wire buffer_valid,
    output wire [1:0] buffer_first_row,
    input wire buffer_release,
    input wire read_enable,
    input wire [9:0] read_addr,
    output wire [127:0] read_data,
    output wire read_valid
);
    wire [127:0] stream_data;
    wire stream_valid, stream_ready, stream_last, core_rho_ready, core_ready, empty;
    wire [3:0] poly_idx;
    wire [5:0] word_idx;
    assign rho_ready = core_rho_ready && empty;
    assign expand_a_ready = core_ready && empty;
    expanda_top #(.PARALLEL_LANES(PARALLEL_LANES)) generator (
        .clk(clk),.rst(rst),.rho_data(rho_data),.rho_valid(rho_valid && empty),
        .rho_ready(core_rho_ready),.rho_loaded(rho_loaded),
        .expand_a_start(expand_a_start && empty),.expand_a_ready(core_ready),
        .expand_a_busy(expand_a_busy),.expand_a_done(expand_a_done),.expand_a_error(expand_a_error),
        .sampled_poly_data(stream_data),.sampled_poly_valid(stream_valid),.sampled_poly_ready(stream_ready),
        .sampled_poly_idx(poly_idx),.sampled_word_idx(word_idx),.sampled_poly_last(stream_last)
    );
    expanda_matrix_buffer #(.ROWS(ROWS)) buffer (
        .clk(clk),.rst(rst || expand_a_error),.stream_data(stream_data),.stream_valid(stream_valid),
        .stream_ready(stream_ready),.stream_poly_idx(poly_idx),.stream_word_idx(word_idx),.stream_last(stream_last),
        .buffer_valid(buffer_valid),.buffer_first_row(buffer_first_row),.buffer_release(buffer_release),
        .read_enable(read_enable),.read_addr(read_addr),.read_data(read_data),.read_valid(read_valid),.buffer_empty(empty)
    );
endmodule
