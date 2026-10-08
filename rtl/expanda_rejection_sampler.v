// Original project implementation. ML-DSA-44 RejNTTPoly byte-stream sampler.
`timescale 1ns/1ps
module expanda_rejection_sampler (
    input wire clk, rst,
    input wire start,
    input wire [7:0] byte_data,
    input wire byte_valid,
    output wire byte_ready,
    output reg [22:0] coeff_data,
    output reg coeff_valid,
    input wire coeff_ready,
    output wire coeff_last,
    output reg busy, done
);
    reg [1:0] byte_index;
    reg [15:0] candidate_low;
    reg [8:0] accepted_count;
    wire [22:0] candidate = {byte_data[6:0], candidate_low};
    // One pending coefficient: stop input until it is accepted downstream.
    assign byte_ready = busy && !coeff_valid;
    assign coeff_last = coeff_valid && (accepted_count == 9'd255);
    always @(posedge clk) begin
        if (rst) begin
            byte_index <= 0; candidate_low <= 0; accepted_count <= 0;
            coeff_data <= 0; coeff_valid <= 0; busy <= 0; done <= 0;
        end else begin
            done <= 0;
            if (start && !busy) begin
                byte_index <= 0; candidate_low <= 0; accepted_count <= 0;
                coeff_valid <= 0; busy <= 1;
            end else begin
                if (byte_valid && byte_ready) begin
                    case (byte_index)
                        0: begin candidate_low[7:0] <= byte_data; byte_index <= 1; end
                        1: begin candidate_low[15:8] <= byte_data; byte_index <= 2; end
                        2: begin
                            byte_index <= 0;
                            if (candidate < 23'd8380417) begin
                                coeff_data <= candidate;
                                coeff_valid <= 1;
                            end
                        end
                        default: byte_index <= 0;
                    endcase
                end
                if (coeff_valid && coeff_ready) begin
                    coeff_valid <= 0;
                    accepted_count <= accepted_count + 1'b1;
                    if (accepted_count == 255) begin busy <= 0; done <= 1; end
                end
            end
        end
    end
endmodule
