`timescale 1ns/1ps
// One 24-bit candidate per transfer; pipelined ready/valid coefficient output.
module expanda_rej_ntt_poly (
    input wire clk, rst, sampler_start,
    input wire [23:0] sample_data,
    input wire sample_valid,
    output wire sample_req,
    output reg [22:0] coeff_data,
    output reg [7:0] coeff_idx,
    output reg coeff_valid,
    input wire coeff_ready,
    output reg sampler_done
);
    reg busy;
    reg [8:0] generated_count;
    wire slot_ready = !coeff_valid || coeff_ready;
    assign sample_req = busy && generated_count < 256 && slot_ready && !rst;
    always @(posedge clk) begin
        if (rst) begin
            busy <= 0; generated_count <= 0; coeff_data <= 0;
            coeff_idx <= 0; coeff_valid <= 0; sampler_done <= 0;
        end else begin
            sampler_done <= 0;
            if (sampler_start) begin busy <= 1; generated_count <= 0; coeff_valid <= 0; end
            else begin
                if (coeff_valid && coeff_ready) begin
                    coeff_valid <= 0;
                    if (coeff_idx == 255) begin busy <= 0; sampler_done <= 1; end
                end
                if (sample_valid && sample_req && sample_data[22:0] < 23'd8380417) begin
                    coeff_data <= sample_data[22:0]; coeff_idx <= generated_count[7:0];
                    coeff_valid <= 1; generated_count <= generated_count + 1'b1;
                end
            end
        end
    end
endmodule
