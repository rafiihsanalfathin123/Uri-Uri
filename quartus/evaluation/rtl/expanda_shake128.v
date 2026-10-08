// SPDX-License-Identifier: MIT
// Fixed SHAKE128, byte-aligned input, 128-bit streaming interface.
// Algorithm: FIPS 202, Keccak-f[1600]. This is an independent implementation,
// not a translated/copy-pasted version of the ML-DSA-OSH core.
//
// MEMORY POLICY
//   25 x 64-bit state + 5 x 64-bit reusable scratch + 64-bit rotation carry
//   + ONE 128-bit buffer shared between absorb and squeeze = 2112 data bits.
//   No full-rate input buffer, full-rate output buffer or second full state.
//   Additional small counters/flags are reported separately.
//
// BYTE ORDER: first byte is shake_in_data[7:0]/shake_out_data[7:0].
// shake_init is a one-cycle pulse; it starts/aborts a job and clears the state.
// Input is accepted on in_valid && in_ready, with nbytes in 1..16.
// Pulse finalize once, after the last input handshake (same cycle also works).
// The accepted input buffer is drained before final padding is applied.
// Hold squeeze_en to request continuous output, or request one word at a time.
// A requested output word finishes even if squeeze_en is subsequently lowered.
// out_data/out_valid remain stable under backpressure. Every output word has
// 16 valid bytes; the consumer truncates/discards an unneeded final suffix.
// phase_done pulses for init, completion of finalize, and an output handshake.
// Invalid nbytes/finalize commands cause sticky error until init or reset.
// Only one active job is supported; no context preemption/save/restore.

// Project derivative: PARALLEL_LANES=5 parallelizes theta and chi rows.
// PARALLEL_LANES=1 preserves the supplied serial schedule for comparison.
// Main writable data banks remain 2112 bits; third-party original is unchanged.
`timescale 1ns/1ps
`default_nettype none

module expanda_shake128 #(parameter PARALLEL_LANES = 5) (
    input  wire         clk,
    input  wire         rst,                 // synchronous, active high
    input  wire         shake_init,
    input  wire         shake_absorb_en,
    input  wire         shake_finalize,
    input  wire         shake_squeeze_en,
    input  wire [127:0] shake_in_data,
    input  wire         shake_in_valid,
    input  wire [4:0]   shake_in_nbytes,
    output wire         shake_in_ready,
    output wire [127:0] shake_out_data,
    output wire         shake_out_valid,
    input  wire         shake_out_ready,
    output wire         shake_ready,
    output reg          shake_phase_done,
    output reg          shake_error
);

    localparam [3:0]
        ST_IDLE        = 4'd0,
        ST_ABSORB      = 4'd1,
        ST_PAD_SUFFIX  = 4'd2,
        ST_PAD_LAST    = 4'd3,
        ST_PERM_START  = 4'd4,
        ST_THETA_ACC   = 4'd5,
        ST_THETA_WRITE = 4'd6,
        ST_RPI_LOAD    = 4'd7,
        ST_RPI_MOVE    = 4'd8,
        ST_CHI_LOAD    = 4'd9,
        ST_CHI_WRITE   = 4'd10,
        ST_IOTA        = 4'd11,
        ST_SQ_IDLE     = 4'd12,
        ST_SQ_READ     = 4'd13,
        ST_SQ_VALID    = 4'd14,
        ST_ERROR       = 4'd15;

    localparam [1:0] RET_ABSORB = 2'd0,
                     RET_FINAL  = 2'd1,
                     RET_SQ     = 2'd2;

    reg [1599:0] a;              // 25 packed lanes, lane x+5*y at bits 64*(x+5*y) +: 64
    reg [319:0] scratch;         // 5 packed lanes: theta parity OR chi row, reused
    reg [63:0] rpi_carry;        // in-place rho/pi cycle, not a second state
    reg [127:0] io_word;         // shared input/output staging register

    reg [3:0] fsm;
    reg [1:0] perm_return;
    reg [4:0] in_remaining;
    reg [3:0] out_fill;
    reg [7:0] byte_pos;          // rate position: 0..167
    reg [4:0] lane_index;
    reg [2:0] column_index;
    reg [4:0] round_index;
    reg [4:0] rpi_step;
    reg [4:0] row_base;          // 0,5,10,15,20
    reg absorbing;
    reg finalize_pending;
    reg squeeze_block_exhausted;
    integer k;

    wire [2:0] prev_column = (column_index == 3'd0) ?
                              3'd4 : column_index - 3'd1;
    wire [2:0] next_column = (column_index == 3'd4) ?
                              3'd0 : column_index + 3'd1;
    wire [2:0] next2_column = (column_index >= 3'd3) ?
                               column_index - 3'd3 : column_index + 3'd2;
    wire [5:0] byte_shift = {byte_pos[2:0], 3'b000};

    assign shake_in_ready = !rst && !shake_init && !shake_error &&
                            (fsm == ST_ABSORB) && (in_remaining == 0) &&
                            !finalize_pending && shake_absorb_en;
    assign shake_out_valid = !rst && !shake_init && !shake_error &&
                             (fsm == ST_SQ_VALID);
    assign shake_out_data = io_word;
    assign shake_ready = !rst && !shake_init && !shake_error &&
                         ((fsm == ST_IDLE) || (fsm == ST_SQ_IDLE) ||
                          ((fsm == ST_ABSORB) && (in_remaining == 0) &&
                           !finalize_pending));

    function [63:0] rol64;
        input [63:0] value;
        input [5:0] amount;
        begin
            if (amount == 0)
                rol64 = value;
            else
                rol64 = (value << amount) |
                        (value >> (7'd64 - {1'b0, amount}));
        end
    endfunction

    // Pi's 24-lane cycle. Lane (0,0) remains in place.
    function [4:0] pi_destination;
        input [4:0] step;
        begin
            case (step)
                 0: pi_destination = 10;  1: pi_destination =  7;
                 2: pi_destination = 11;  3: pi_destination = 17;
                 4: pi_destination = 18;  5: pi_destination =  3;
                 6: pi_destination =  5;  7: pi_destination = 16;
                 8: pi_destination =  8;  9: pi_destination = 21;
                10: pi_destination = 24; 11: pi_destination =  4;
                12: pi_destination = 15; 13: pi_destination = 23;
                14: pi_destination = 19; 15: pi_destination = 13;
                16: pi_destination = 12; 17: pi_destination =  2;
                18: pi_destination = 20; 19: pi_destination = 14;
                20: pi_destination = 22; 21: pi_destination =  9;
                22: pi_destination =  6; 23: pi_destination =  1;
                default: pi_destination = 0;
            endcase
        end
    endfunction

    function [5:0] rho_rotation;
        input [4:0] step;
        begin
            case (step)
                 0: rho_rotation =  1;  1: rho_rotation =  3;
                 2: rho_rotation =  6;  3: rho_rotation = 10;
                 4: rho_rotation = 15;  5: rho_rotation = 21;
                 6: rho_rotation = 28;  7: rho_rotation = 36;
                 8: rho_rotation = 45;  9: rho_rotation = 55;
                10: rho_rotation =  2; 11: rho_rotation = 14;
                12: rho_rotation = 27; 13: rho_rotation = 41;
                14: rho_rotation = 56; 15: rho_rotation =  8;
                16: rho_rotation = 25; 17: rho_rotation = 43;
                18: rho_rotation = 62; 19: rho_rotation = 18;
                20: rho_rotation = 39; 21: rho_rotation = 61;
                22: rho_rotation = 20; 23: rho_rotation = 44;
                default: rho_rotation = 0;
            endcase
        end
    endfunction

    function [63:0] round_constant;
        input [4:0] round;
        begin
            case (round)
                 0: round_constant = 64'h0000000000000001;
                 1: round_constant = 64'h0000000000008082;
                 2: round_constant = 64'h800000000000808a;
                 3: round_constant = 64'h8000000080008000;
                 4: round_constant = 64'h000000000000808b;
                 5: round_constant = 64'h0000000080000001;
                 6: round_constant = 64'h8000000080008081;
                 7: round_constant = 64'h8000000000008009;
                 8: round_constant = 64'h000000000000008a;
                 9: round_constant = 64'h0000000000000088;
                10: round_constant = 64'h0000000080008009;
                11: round_constant = 64'h000000008000000a;
                12: round_constant = 64'h000000008000808b;
                13: round_constant = 64'h800000000000008b;
                14: round_constant = 64'h8000000000008089;
                15: round_constant = 64'h8000000000008003;
                16: round_constant = 64'h8000000000008002;
                17: round_constant = 64'h8000000000000080;
                18: round_constant = 64'h000000000000800a;
                19: round_constant = 64'h800000008000000a;
                20: round_constant = 64'h8000000080008081;
                21: round_constant = 64'h8000000000008080;
                22: round_constant = 64'h0000000080000001;
                23: round_constant = 64'h8000000080008008;
                default: round_constant = 0;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst || shake_init) begin
            for (k = 0; k < 25; k = k + 1)
                a[(k)*64 +: 64] <= 64'd0;
            for (k = 0; k < 5; k = k + 1)
                scratch[(k)*64 +: 64] <= 64'd0;
            rpi_carry <= 0;
            io_word <= 0;
            fsm <= rst ? ST_IDLE : ST_ABSORB;
            perm_return <= RET_ABSORB;
            in_remaining <= 0;
            out_fill <= 0;
            byte_pos <= 0;
            lane_index <= 0;
            column_index <= 0;
            round_index <= 0;
            rpi_step <= 0;
            row_base <= 0;
            absorbing <= !rst;
            finalize_pending <= 0;
            squeeze_block_exhausted <= 0;
            shake_phase_done <= !rst;
            shake_error <= 0;
        end else begin
            shake_phase_done <= 0;

            if (shake_finalize && (!absorbing || finalize_pending)) begin
                shake_error <= 1;
                fsm <= ST_ERROR;
            end else begin
                if (shake_finalize)
                    finalize_pending <= 1;

                case (fsm)
                    ST_IDLE: begin
                        // Wait for explicit shake_init.
                    end

                    ST_ABSORB: begin
                        if (in_remaining != 0) begin
                            a[(byte_pos[7:3])*64 +: 64] <= a[(byte_pos[7:3])*64 +: 64] ^
                                ({56'd0, io_word[7:0]} << byte_shift);
                            io_word <= io_word >> 8;
                            in_remaining <= in_remaining - 1'b1;
                            if (byte_pos == 8'd167) begin
                                byte_pos <= 0;
                                perm_return <= RET_ABSORB;
                                fsm <= ST_PERM_START;
                            end else begin
                                byte_pos <= byte_pos + 1'b1;
                            end
                        end else if (finalize_pending) begin
                            absorbing <= 0;
                            fsm <= ST_PAD_SUFFIX;
                        end else if (shake_in_valid && shake_in_ready) begin
                            if ((shake_in_nbytes == 0) ||
                                (shake_in_nbytes > 16)) begin
                                shake_error <= 1;
                                fsm <= ST_ERROR;
                            end else begin
                                io_word <= shake_in_data;
                                in_remaining <= shake_in_nbytes;
                            end
                        end
                    end

                    ST_PAD_SUFFIX: begin
                        // XOR suffix into the current rate byte. Zero padding
                        // requires no storage or writes: XOR zero is a no-op.
                        a[(byte_pos[7:3])*64 +: 64] <= a[(byte_pos[7:3])*64 +: 64] ^
                                           (64'h1f << byte_shift);
                        fsm <= ST_PAD_LAST;
                    end

                    ST_PAD_LAST: begin
                        // Separate cycle avoids overlapping writes when the
                        // suffix and final bit share a lane/byte (0x9f case).
                        a[(20)*64 +: 64] <= a[(20)*64 +: 64] ^ 64'h8000000000000000;
                        perm_return <= RET_FINAL;
                        fsm <= ST_PERM_START;
                    end

                    ST_PERM_START: begin
                        round_index <= 0;
                        lane_index <= 0;
                        column_index <= 0;
                        for (k = 0; k < 5; k = k + 1)
                            scratch[(k)*64 +: 64] <= 0;
                        fsm <= ST_THETA_ACC;
                    end

                    ST_THETA_ACC: begin
                        if (PARALLEL_LANES == 5) begin
                            for (k = 0; k < 5; k = k + 1)
                                case (lane_index)
                                    0: scratch[k*64 +: 64] <= scratch[k*64 +: 64] ^ a[k*64 +: 64];
                                    5: scratch[k*64 +: 64] <= scratch[k*64 +: 64] ^ a[(5+k)*64 +: 64];
                                    10: scratch[k*64 +: 64] <= scratch[k*64 +: 64] ^ a[(10+k)*64 +: 64];
                                    15: scratch[k*64 +: 64] <= scratch[k*64 +: 64] ^ a[(15+k)*64 +: 64];
                                    20: scratch[k*64 +: 64] <= scratch[k*64 +: 64] ^ a[(20+k)*64 +: 64];
                                    default: begin shake_error <= 1; fsm <= ST_ERROR; end
                                endcase
                            if (lane_index == 20) begin
                                lane_index <= 0;
                                fsm <= ST_THETA_WRITE;
                            end else lane_index <= lane_index + 5'd5;
                        end else begin

                        scratch[(column_index)*64 +: 64] <= scratch[(column_index)*64 +: 64] ^
                                                 a[(lane_index)*64 +: 64];
                        if (lane_index == 24) begin
                            lane_index <= 0;
                            column_index <= 0;
                            fsm <= ST_THETA_WRITE;
                        end else begin
                            lane_index <= lane_index + 1'b1;
                            column_index <= next_column;
                        end
                                            end
                    end

                    ST_THETA_WRITE: begin
                        if (PARALLEL_LANES == 5) begin
                            for (k = 0; k < 5; k = k + 1)
                                begin end
                            for (k = 0; k < 25; k = k + 1)
                                if (lane_index == (k/5)*5)
                                    a[k*64 +: 64] <= a[k*64 +: 64] ^ scratch[((k+4)%5)*64 +: 64] ^
                                        rol64(scratch[((k+1)%5)*64 +: 64], 6'd1);
                            if (lane_index == 20) fsm <= ST_RPI_LOAD;
                            else lane_index <= lane_index + 5'd5;
                        end else begin

                        a[(lane_index)*64 +: 64] <= a[(lane_index)*64 +: 64] ^ scratch[(prev_column)*64 +: 64] ^
                                         rol64(scratch[(next_column)*64 +: 64], 6'd1);
                        if (lane_index == 24) begin
                            fsm <= ST_RPI_LOAD;
                        end else begin
                            lane_index <= lane_index + 1'b1;
                            column_index <= next_column;
                        end
                                            end
                    end

                    ST_RPI_LOAD: begin
                        rpi_carry <= a[(1)*64 +: 64];
                        rpi_step <= 0;
                        fsm <= ST_RPI_MOVE;
                    end

                    ST_RPI_MOVE: begin
                        rpi_carry <= a[(pi_destination(rpi_step))*64 +: 64];
                        a[(pi_destination(rpi_step))*64 +: 64] <=
                            rol64(rpi_carry, rho_rotation(rpi_step));
                        if (rpi_step == 23) begin
                            row_base <= 0;
                            fsm <= ST_CHI_LOAD;
                        end else begin
                            rpi_step <= rpi_step + 1'b1;
                        end
                    end

                    ST_CHI_LOAD: begin
                        if (PARALLEL_LANES == 5) begin
                            for (k = 0; k < 5; k = k + 1)
                                case (row_base)
                                    0: scratch[k*64 +: 64] <= a[k*64 +: 64];
                                    5: scratch[k*64 +: 64] <= a[(5+k)*64 +: 64];
                                    10: scratch[k*64 +: 64] <= a[(10+k)*64 +: 64];
                                    15: scratch[k*64 +: 64] <= a[(15+k)*64 +: 64];
                                    20: scratch[k*64 +: 64] <= a[(20+k)*64 +: 64];
                                    default: begin shake_error <= 1; fsm <= ST_ERROR; end
                                endcase
                            column_index <= 0;
                            fsm <= ST_CHI_WRITE;
                        end else begin

                        // Reuse the former theta scratch as one chi row.
                        for (k = 0; k < 5; k = k + 1)
                            scratch[(k)*64 +: 64] <= a[(row_base + k)*64 +: 64];
                        column_index <= 0;
                        fsm <= ST_CHI_WRITE;
                                            end
                    end

                    ST_CHI_WRITE: begin
                        if (PARALLEL_LANES == 5) begin
                            for (k = 0; k < 25; k = k + 1)
                                if (row_base == (k/5)*5)
                                    a[k*64 +: 64] <= scratch[(k%5)*64 +: 64] ^
                                        ((~scratch[((k+1)%5)*64 +: 64]) & scratch[((k+2)%5)*64 +: 64]);
                            if (row_base == 20) fsm <= ST_IOTA;
                            else begin row_base <= row_base + 5'd5; fsm <= ST_CHI_LOAD; end
                        end else begin

                        a[(row_base + column_index)*64 +: 64] <= scratch[(column_index)*64 +: 64] ^
                            ((~scratch[(next_column)*64 +: 64]) & scratch[(next2_column)*64 +: 64]);
                        if (column_index == 4) begin
                            if (row_base == 20)
                                fsm <= ST_IOTA;
                            else begin
                                row_base <= row_base + 5'd5;
                                fsm <= ST_CHI_LOAD;
                            end
                        end else begin
                            column_index <= column_index + 1'b1;
                        end
                                            end
                    end

                    ST_IOTA: begin
                        a[(0)*64 +: 64] <= a[(0)*64 +: 64] ^ round_constant(round_index);
                        if (round_index == 23) begin
                            case (perm_return)
                                RET_ABSORB: fsm <= ST_ABSORB;
                                RET_FINAL: begin
                                    fsm <= ST_SQ_IDLE;
                                    finalize_pending <= 0;
                                    byte_pos <= 0;
                                    out_fill <= 0;
                                    io_word <= 0;
                                    squeeze_block_exhausted <= 0;
                                    shake_phase_done <= 1;
                                end
                                RET_SQ: fsm <= ST_SQ_READ;
                                default: begin
                                    shake_error <= 1;
                                    fsm <= ST_ERROR;
                                end
                            endcase
                        end else begin
                            round_index <= round_index + 1'b1;
                            lane_index <= 0;
                            column_index <= 0;
                            for (k = 0; k < 5; k = k + 1)
                                scratch[(k)*64 +: 64] <= 0;
                            fsm <= ST_THETA_ACC;
                        end
                    end

                    ST_SQ_IDLE: begin
                        if (shake_squeeze_en) begin
                            if (squeeze_block_exhausted) begin
                                squeeze_block_exhausted <= 0;
                                perm_return <= RET_SQ;
                                fsm <= ST_PERM_START;
                            end else begin
                                fsm <= ST_SQ_READ;
                            end
                        end
                    end

                    ST_SQ_READ: begin
                        io_word[{out_fill, 3'b000} +: 8] <=
                            a[(byte_pos[7:3])*64 +: 64] >> byte_shift;
                        if (byte_pos == 167)
                            byte_pos <= 0;
                        else
                            byte_pos <= byte_pos + 1'b1;

                        if (out_fill == 15) begin
                            out_fill <= 0;
                            squeeze_block_exhausted <= (byte_pos == 167);
                            fsm <= ST_SQ_VALID;
                        end else begin
                            out_fill <= out_fill + 1'b1;
                            if (byte_pos == 167) begin
                                // Keep the partial output word across squeeze
                                // permutations; never discard its last 8 bytes.
                                perm_return <= RET_SQ;
                                fsm <= ST_PERM_START;
                            end
                        end
                    end

                    ST_SQ_VALID: begin
                        if (shake_out_ready) begin
                            shake_phase_done <= 1;
                            fsm <= ST_SQ_IDLE;
                        end
                    end

                    ST_ERROR: begin
                        // Recovery is explicit shake_init or rst.
                    end

                    default: begin
                        shake_error <= 1;
                        fsm <= ST_ERROR;
                    end
                endcase
            end
        end
    end
endmodule

`default_nettype wire
