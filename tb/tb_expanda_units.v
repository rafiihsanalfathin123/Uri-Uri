`timescale 1ns/1ps
module tb_expanda_units;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,start=0,source_enable=0,output_ready=0;
    reg [127:0] input_words[0:63],expected_words[0:45];
    wire [127:0] word_data=input_words[input_idx];
    wire word_valid=source_enable && input_idx<64;
    wire word_ready;
    wire [23:0] sample_data;
    wire sample_valid,sample_req;
    wire [22:0] coeff_data;
    wire [7:0] coeff_idx;
    wire coeff_valid,coeff_ready,sampler_done;
    wire [127:0] packed_data;
    wire packed_valid,packed_last,poly_done,error;
    wire [3:0] poly_idx;
    wire [5:0] word_idx;
    integer input_idx=0,outputs=0,accepted=0,rejected=0,checking=0,cycle=0;
    reg tb_pass=0,prev_stall=0;
    reg [127:0] held;
    reg [5:0] held_idx;
    expanda_xof_buffer buffer (.clk(clk),.rst(rst),.flush(start || sampler_done),
        .shake_out_data(word_data),.shake_out_valid(word_valid),.shake_out_ready(word_ready),
        .sample_data(sample_data),.sample_valid(sample_valid),.sample_req(sample_req));
    expanda_rej_ntt_poly sampler (.clk(clk),.rst(rst),.sampler_start(start),
        .sample_data(sample_data),.sample_valid(sample_valid),.sample_req(sample_req),
        .coeff_data(coeff_data),.coeff_idx(coeff_idx),.coeff_valid(coeff_valid),.coeff_ready(coeff_ready),.sampler_done(sampler_done));
    expanda_output_packer packer (.clk(clk),.rst(rst),.packer_start(start),.poly_idx(4'd10),
        .coeff_data(coeff_data),.coeff_idx(coeff_idx),.coeff_valid(coeff_valid),.coeff_ready(coeff_ready),
        .sampled_poly_data(packed_data),.sampled_poly_valid(packed_valid),.sampled_poly_ready(output_ready),
        .sampled_poly_idx(poly_idx),.sampled_word_idx(word_idx),.sampled_poly_last(packed_last),
        .packer_poly_done(poly_done),.packer_error(error));
    task fail;input [1023:0] message;begin $display("FAIL: units %0s",message);$finish;end endtask
    always @(negedge clk) output_ready=!rst && cycle%29>=14;
    always @(posedge clk) begin
        cycle=cycle+1;
        if(rst) prev_stall=0;
        if(word_valid && word_ready) input_idx<=input_idx+1;
        if(sampler_done) source_enable=0;
        if(checking && !rst) begin
            if(error) fail("packer index error");
            if(prev_stall && (!packed_valid || packed_data!==held || word_idx!==held_idx)) fail("unstable packed output");
            prev_stall=packed_valid && !output_ready;held=packed_data;held_idx=word_idx;
            if(sample_valid && sample_req && sample_data[22:0]>=8380417) rejected=rejected+1;
            if(coeff_valid && coeff_ready) begin
                if(coeff_idx!==accepted) fail("accepted index");
                accepted=accepted+1;
            end
            if(packed_valid && output_ready) begin
                if(packed_data!==expected_words[outputs] || poly_idx!=10 || word_idx!==outputs ||
                    packed_last!==(outputs==45)) begin
                    $display("word=%0d expected=%032h actual=%032h",outputs,expected_words[outputs],packed_data);
                    fail("directed packed data/tags");
                end
                outputs=outputs+1;
            end
        end
    end
    initial begin
        $readmemh("vectors/unit_xof_words.hex",input_words);
        $readmemh("vectors/unit_packed_words.hex",expected_words);
        repeat(3) @(negedge clk);rst=0;start=1;
        @(negedge clk);start=0;source_enable=1;
        repeat(7) @(negedge clk);rst=1;source_enable=0;
        repeat(3) @(negedge clk);input_idx=0;rst=0;start=1;
        @(negedge clk);start=0;source_enable=1;checking=1;
        wait(poly_done);@(negedge clk);
        if(outputs!=46 || accepted!=256 || rejected<3) fail("wrong directed coverage counts");
        tb_pass=1;$display("PASS: units 256 coefficients, 46 packed words, %0d rejects, q boundaries/high-bit masking, cross-word candidates, stalls and partial reset",rejected);$finish;
    end
    initial begin #1000000;fail("timeout");end
endmodule
