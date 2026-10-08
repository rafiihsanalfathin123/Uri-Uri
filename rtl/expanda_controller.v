`timescale 1ns/1ps
module expanda_controller (
    input wire clk, rst, expand_a_start, rho_loaded, absorb_done,
    input wire shake_phase_done, sampler_done, packer_poly_done, error_in,
    output wire expand_a_ready, seed_use, seed_absorb_start, shake_init,
    output wire shake_finalize, shake_squeeze_en, sampler_start, packer_start, xof_flush,
    output reg [1:0] row_idx, col_idx,
    output wire expand_a_busy,
    output reg expand_a_done, expand_a_error
);
    localparam IDLE=0, INIT=1, SEED_START=2, ABSORB=3,
               FINALIZE=4, WAIT_FINAL=5, SQUEEZE=6, DRAIN=7;
    reg [2:0] state;
    wire enabled = !rst && !expand_a_error && !error_in;
    assign expand_a_ready = enabled && state == IDLE && rho_loaded;
    assign seed_use = expand_a_start && expand_a_ready;
    assign expand_a_busy = enabled && state != IDLE;
    assign seed_absorb_start = enabled && state == SEED_START;
    assign shake_init = enabled && ((state == INIT) || sampler_done);
    assign shake_finalize = enabled && state == FINALIZE;
    assign shake_squeeze_en = enabled && state == SQUEEZE && !sampler_done;
    assign sampler_start = enabled && state == INIT;
    assign packer_start = sampler_start;
    assign xof_flush = !enabled || state == INIT || sampler_done;
    always @(posedge clk) begin
        if (rst) begin state <= IDLE; row_idx <= 0; col_idx <= 0; expand_a_done <= 0; expand_a_error <= 0; end
        else begin
            expand_a_done <= 0;
            if (error_in) begin expand_a_error <= 1; state <= IDLE; end
            else if (expand_a_error) state <= IDLE;
            else case (state)
                IDLE: if (seed_use) begin row_idx <= 0; col_idx <= 0; state <= INIT; end
                INIT: state <= SEED_START;
                SEED_START: state <= ABSORB;
                ABSORB: if (absorb_done) state <= FINALIZE;
                FINALIZE: state <= WAIT_FINAL;
                WAIT_FINAL: if (shake_phase_done) state <= SQUEEZE;
                SQUEEZE: if (sampler_done) state <= DRAIN;
                DRAIN: if (packer_poly_done) begin
                    if (row_idx == 3 && col_idx == 3) begin expand_a_done <= 1; state <= IDLE; end
                    else begin
                        if (col_idx == 3) begin col_idx <= 0; row_idx <= row_idx + 1'b1; end
                        else col_idx <= col_idx + 1'b1;
                        state <= INIT;
                    end
                end
                default: begin state <= IDLE; expand_a_error <= 1; end
            endcase
        end
    end
endmodule
