`timescale 1ns/1ps
// Diagram-aligned ExpandA-44 producer. Verilog-2001; no matrix RAM.
module expanda_top #(parameter PARALLEL_LANES = 5) (
    input wire clk, rst,
    input wire [127:0] rho_data,
    input wire rho_valid,
    output wire rho_ready, rho_loaded,
    input wire expand_a_start,
    output wire expand_a_ready, expand_a_busy, expand_a_done, expand_a_error,
    output wire [127:0] sampled_poly_data,
    output wire sampled_poly_valid,
    input wire sampled_poly_ready,
    output wire [3:0] sampled_poly_idx,
    output wire [5:0] sampled_word_idx,
    output wire sampled_poly_last
);
    wire [1:0] row_idx, col_idx;
    wire seed_use, seed_absorb_start, absorb_done, shake_init, shake_finalize,
         shake_squeeze_en, sampler_start, packer_start, xof_flush;
    wire [127:0] shake_in_data, shake_out_data;
    wire [4:0] shake_in_nbytes;
    wire shake_in_valid, shake_in_ready, shake_out_valid, shake_out_ready,
         shake_phase_done, shake_error, shake_ready;
    wire [23:0] sample_data;
    wire sample_valid, sample_req;
    wire [22:0] coeff_data;
    wire [7:0] coeff_idx;
    wire coeff_valid, coeff_ready, sampler_done, packer_poly_done, packer_error;
    wire error_in = shake_error || packer_error;
    wire internal_rst = rst || expand_a_error || error_in;
    wire engine_word_ready;
    expanda_controller controller (
        .clk(clk),.rst(rst),.expand_a_start(expand_a_start),.rho_loaded(rho_loaded),
        .absorb_done(absorb_done),.shake_phase_done(shake_phase_done),.sampler_done(sampler_done),
        .packer_poly_done(packer_poly_done),.error_in(error_in),.expand_a_ready(expand_a_ready),
        .seed_use(seed_use),.seed_absorb_start(seed_absorb_start),.shake_init(shake_init),
        .shake_finalize(shake_finalize),.shake_squeeze_en(shake_squeeze_en),
        .sampler_start(sampler_start),.packer_start(packer_start),.xof_flush(xof_flush),
        .row_idx(row_idx),.col_idx(col_idx),.expand_a_busy(expand_a_busy),
        .expand_a_done(expand_a_done),.expand_a_error(expand_a_error)
    );
    expanda_seed_absorb seed_capture (
        .clk(clk),.rst(internal_rst),.load_enable(!expand_a_busy),.seed_use(seed_use),
        .seed_absorb_start(seed_absorb_start),.rho_data(rho_data),.rho_valid(rho_valid),
        .rho_ready(rho_ready),.rho_loaded(rho_loaded),.row_idx(row_idx),.col_idx(col_idx),
        .shake_in_data(shake_in_data),.shake_in_nbytes(shake_in_nbytes),
        .shake_in_valid(shake_in_valid),.shake_in_ready(shake_in_ready),.absorb_done(absorb_done)
    );
    expanda_shake128 #(.PARALLEL_LANES(PARALLEL_LANES)) shake (
        .clk(clk),.rst(internal_rst),.shake_init(shake_init),.shake_absorb_en(1'b1),
        .shake_finalize(shake_finalize),.shake_squeeze_en(shake_squeeze_en),
        .shake_in_data(shake_in_data),.shake_in_nbytes(shake_in_nbytes),
        .shake_in_valid(shake_in_valid),.shake_in_ready(shake_in_ready),
        .shake_out_data(shake_out_data),.shake_out_valid(shake_out_valid),
        .shake_out_ready(shake_out_ready),.shake_ready(shake_ready),
        .shake_phase_done(shake_phase_done),.shake_error(shake_error)
    );
    assign shake_out_ready = engine_word_ready && shake_squeeze_en;
    expanda_xof_buffer xof_buffer (
        .clk(clk),.rst(internal_rst),.flush(xof_flush),.shake_out_data(shake_out_data),
        .shake_out_valid(shake_out_valid && shake_squeeze_en),.shake_out_ready(engine_word_ready),
        .sample_data(sample_data),.sample_valid(sample_valid),.sample_req(sample_req)
    );
    expanda_rej_ntt_poly sampler (
        .clk(clk),.rst(internal_rst),.sampler_start(sampler_start),.sample_data(sample_data),
        .sample_valid(sample_valid),.sample_req(sample_req),.coeff_data(coeff_data),
        .coeff_idx(coeff_idx),.coeff_valid(coeff_valid),.coeff_ready(coeff_ready),.sampler_done(sampler_done)
    );
    expanda_output_packer packer (
        .clk(clk),.rst(internal_rst),.packer_start(packer_start),.poly_idx({row_idx,col_idx}),
        .coeff_data(coeff_data),.coeff_idx(coeff_idx),.coeff_valid(coeff_valid),.coeff_ready(coeff_ready),
        .sampled_poly_data(sampled_poly_data),.sampled_poly_valid(sampled_poly_valid),
        .sampled_poly_ready(sampled_poly_ready),.sampled_poly_idx(sampled_poly_idx),
        .sampled_word_idx(sampled_word_idx),.sampled_poly_last(sampled_poly_last),
        .packer_poly_done(packer_poly_done),.packer_error(packer_error)
    );
endmodule
