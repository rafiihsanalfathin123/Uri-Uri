`timescale 1ns/1ps
`ifndef SHAKE_LANES
`define SHAKE_LANES 5
`endif
module tb_expanda_v2;
    localparam LANES = `SHAKE_LANES;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, rho_valid=0, start=0, output_ready=0;
    reg [127:0] rho_data=0;
    wire rho_ready,rho_loaded,ready,busy,done,error,output_valid,output_last;
    wire [127:0] output_data;
    wire [3:0] poly_idx;
    wire [5:0] word_idx;
    reg [255:0] seeds[0:2];
    reg [127:0] expected_words[0:2207];
    reg [7:0] xof[0:57599];
    integer job=0,cycle=0,checking=0,words_job=0,total_words=0,contexts=0;
    integer start_cycle=0,first_word_cycle=0,last_word_cycle=0;
    integer context_start=0,context_index=0,absorbed=0,xof_bytes=0,candidates=0,rejected=0;
    integer coefficients=0,permutations=0,permutation_cycles=0,done_jobs=0;
    integer output_csv,latency_csv,stats_csv,xof_csv,b,expected_index,stall_word=-1,stall_left=0;
    integer stalled_output_cycles=0,stalled_shake_cycles=0;
    reg tb_pass=0;
    reg prev_output_stall=0,prev_shake_stall=0;
    reg [127:0] held_output,held_shake,expected_shake;
    reg [3:0] held_poly;
    reg [5:0] held_index;
    reg held_last;
    reg [7:0] expected_byte;
    expanda_top #(.PARALLEL_LANES(LANES)) dut (
        .clk(clk),.rst(rst),.rho_data(rho_data),.rho_valid(rho_valid),.rho_ready(rho_ready),.rho_loaded(rho_loaded),
        .expand_a_start(start),.expand_a_ready(ready),.expand_a_busy(busy),.expand_a_done(done),.expand_a_error(error),
        .sampled_poly_data(output_data),.sampled_poly_valid(output_valid),.sampled_poly_ready(output_ready),
        .sampled_poly_idx(poly_idx),.sampled_word_idx(word_idx),.sampled_poly_last(output_last)
    );
    task fail;
        input [1023:0] message;
        begin $display("FAIL: %0s job=%0d cycle=%0d",message,job,cycle); $finish; end
    endtask
    task reset_all;
        begin
            @(negedge clk);rst=1;rho_valid=0;start=0;
            repeat(3) @(negedge clk);rst=0;
            @(negedge clk);
            if(!rho_ready || rho_loaded || ready || error || output_valid || busy || done) fail("reset state");
        end
    endtask
    task load_and_start;
        input [255:0] seed;
        begin
            @(negedge clk);rho_data=seed[127:0];rho_valid=1;
            while(!rho_ready) @(negedge clk);
            @(negedge clk);rho_valid=0;
            repeat(3) @(negedge clk);
            if(rho_loaded || ready) fail("partial seed advertised as loaded");
            rho_data=seed[255:128];rho_valid=1;
            @(negedge clk);rho_valid=0;
            if(!rho_loaded || !ready) fail("second seed beat was not captured");
            start=1;@(negedge clk);start=0;rho_data=~rho_data;
        end
    endtask
    always @(negedge clk) begin
        if(rst) output_ready=0;
        else if(checking && job==3) begin
            if(output_valid && words_job%17==0 && stall_word!=words_job) begin
                stall_word=words_job;stall_left=150;
            end
            if(stall_left>0) begin output_ready=0;stall_left=stall_left-1;end
            else output_ready=1;
        end else output_ready=1;
    end
    always @(posedge clk) begin
        cycle=cycle+1;
        if(rst || !checking) begin prev_output_stall=0;prev_shake_stall=0;end
        else begin
            if(error) fail("unexpected integrated error");
            if(prev_output_stall && (!output_valid || output_data!==held_output ||
                poly_idx!==held_poly || word_idx!==held_index || output_last!==held_last)) fail("packed output changed during stall");
            if(prev_shake_stall && !dut.shake_init &&
                (!dut.shake_out_valid || dut.shake_out_data!==held_shake)) fail("SHAKE output changed during stall");
            prev_output_stall=output_valid && !output_ready;
            prev_shake_stall=dut.shake_out_valid && !dut.shake_out_ready && !dut.shake_init;
            held_output=output_data;held_poly=poly_idx;held_index=word_idx;held_last=output_last;held_shake=dut.shake_out_data;
            if(prev_output_stall) stalled_output_cycles=stalled_output_cycles+1;
            if(prev_shake_stall) stalled_shake_cycles=stalled_shake_cycles+1;
            if(start && ready) begin
                start_cycle=cycle;first_word_cycle=0;last_word_cycle=0;words_job=0;
            end
            if(dut.sampler_start) begin
                context_index=contexts%16;
                if({dut.row_idx,dut.col_idx}!==context_index) fail("context order");
                contexts=contexts+1;context_start=cycle;absorbed=0;xof_bytes=0;
                candidates=0;rejected=0;coefficients=0;permutations=0;permutation_cycles=0;
            end
            if(dut.shake_in_valid && dut.shake_in_ready) begin
                if(dut.shake_in_nbytes!==((absorbed==32)?5'd2:5'd16)) fail("absorb nbytes");
                for(b=0;b<dut.shake_in_nbytes;b=b+1) begin
                    if(absorbed+b<32) expected_byte=seeds[job%3][(absorbed+b)*8+:8];
                    else if(absorbed+b==32) expected_byte={6'd0,dut.col_idx};
                    else expected_byte={6'd0,dut.row_idx};
                    if(dut.shake_in_data[b*8+:8]!==expected_byte) fail("seed/nonce absorb ordering");
                end
                absorbed=absorbed+dut.shake_in_nbytes;
            end
            if(dut.shake_finalize && absorbed!=34) fail("finalize length");
            if(dut.shake.fsm>=4 && dut.shake.fsm<=11) permutation_cycles=permutation_cycles+1;
            if(dut.shake.fsm==4) permutations=permutations+1;
            if(dut.shake_out_valid && dut.shake_out_ready) begin
                for(b=0;b<16;b=b+1) begin
                    expected_shake[b*8+:8]=xof[((job%3)*16+context_index)*1200+xof_bytes+b];
                    if(dut.shake_out_data[b*8+:8]!==expected_shake[b*8+:8]) fail("actual SHAKE bytes");
                end
                $fdisplay(xof_csv,"%0d,%0d,%0d,%032h,%032h",job,context_index,xof_bytes,expected_shake,dut.shake_out_data);
                xof_bytes=xof_bytes+16;
            end
            if(dut.sample_valid && dut.sample_req) begin
                candidates=candidates+1;
                if(dut.sample_data[22:0]>=8380417) rejected=rejected+1;
            end
            if(dut.coeff_valid && dut.coeff_ready) begin
                if(dut.coeff_idx!==coefficients) fail("coefficient index");
                coefficients=coefficients+1;
            end
            if(output_valid && output_ready) begin
                expected_index=(job%3)*736+words_job;
                if(output_data!==expected_words[expected_index]) fail("128-bit packed output");
                if(poly_idx!==(words_job/46) || word_idx!==(words_job%46) ||
                    output_last!==(words_job%46==45)) fail("packed output tags");
                $fdisplay(output_csv,"%0d,%0d,%0d,%032h,%032h,1",job,poly_idx,word_idx,expected_words[expected_index],output_data);
                if(words_job==0) first_word_cycle=cycle;
                if(output_last) begin
                    if(coefficients!=256 || candidates-rejected!=256 || absorbed!=34) fail("polynomial completion counts");
                    $fdisplay(stats_csv,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",job,poly_idx,
                        cycle-context_start,xof_bytes,candidates,rejected,coefficients,permutations,permutation_cycles);
                end
                last_word_cycle=cycle;words_job=words_job+1;total_words=total_words+1;
            end
        end
        #1;
        if(checking && done) begin
            if(words_job!=736) fail("wrong output length at done");
            $fdisplay(latency_csv,"%0d,%0d,%0d,%0d,%0d",job,first_word_cycle-start_cycle,
                last_word_cycle-start_cycle,cycle-start_cycle,job==3);
            done_jobs=done_jobs+1;
        end
    end
    initial begin
        if(LANES==5) $dumpfile("results/v2_fast/expanda.vcd");
        else $dumpfile("results/v2_serial/expanda.vcd");
        $dumpvars(1,tb_expanda_v2);
        $dumpvars(0,dut.controller.state,dut.row_idx,dut.col_idx,dut.shake_init,dut.shake_finalize,
            dut.shake_in_valid,dut.shake_in_ready,dut.shake_in_data,dut.shake_in_nbytes,
            dut.shake_out_valid,dut.shake_out_ready,dut.shake_out_data,dut.shake.fsm,
            dut.sample_valid,dut.sample_req,dut.sample_data,dut.coeff_valid,dut.coeff_ready,dut.coeff_data,dut.coeff_idx);
        $readmemh("vectors/integrated_seeds.hex",seeds);
        $readmemh("vectors/packed_words.hex",expected_words);
        $readmemh("vectors/integrated_xof.hex",xof);
        if(LANES==5) begin
            output_csv=$fopen("results/v2_fast/output.csv","w");
            latency_csv=$fopen("results/v2_fast/latency.csv","w");
            stats_csv=$fopen("results/v2_fast/polynomials.csv","w");
            xof_csv=$fopen("results/v2_fast/xof.csv","w");
        end else begin
            output_csv=$fopen("results/v2_serial/output.csv","w");
            latency_csv=$fopen("results/v2_serial/latency.csv","w");
            stats_csv=$fopen("results/v2_serial/polynomials.csv","w");
            xof_csv=$fopen("results/v2_serial/xof.csv","w");
        end
        if(!output_csv || !latency_csv || !stats_csv || !xof_csv) fail("result file creation");
        $fdisplay(output_csv,"job,poly,word,expected_hex,actual_hex,match");
        $fdisplay(latency_csv,"job,first_word_cycles,last_word_cycles,done_cycles,stress");
        $fdisplay(stats_csv,"job,poly,cycles,xof_bytes,candidates,rejected,coefficients,permutations,permutation_cycles");
        $fdisplay(xof_csv,"job,poly,byte_offset,expected_hex,actual_hex");
        reset_all;
        start=1;@(negedge clk);start=0;
        if(busy || ready) fail("unseeded start accepted");
        load_and_start(256'hdeadbeef);
        wait(dut.shake.fsm==5);repeat(7) @(negedge clk);reset_all;
        checking=1;
        for(job=0;job<3;job=job+1) begin
            load_and_start(seeds[job]);
            repeat(100) @(negedge clk);
            // Busy start and seed writes must not corrupt the context.
            start=1;rho_valid=1;rho_data=128'hbadbad;
            @(negedge clk);start=0;rho_valid=0;
            wait(done);repeat(3) @(negedge clk);
        end
        checking=0;
        // Reset with an outstanding packed word (not only during permutation).
        load_and_start(seeds[0]);
        wait(output_valid);@(negedge clk);rst=1;
        repeat(3) @(negedge clk);rst=0;
        checking=1;job=3;stall_word=-1;stall_left=0;
        load_and_start(seeds[0]);wait(done);repeat(3) @(negedge clk);
        if(total_words!=2944 || contexts!=64 || done_jobs!=4 || stalled_output_cycles<100 || stalled_shake_cycles<1)
            fail("regression coverage counts");
        checking=0;
        load_and_start(seeds[0]);wait(dut.shake.fsm==5);
        force dut.shake.shake_error=1'b1;repeat(2) @(negedge clk);
        release dut.shake.shake_error;repeat(3) @(negedge clk);
        if(!error || busy || ready || rho_ready || output_valid || done) fail("sticky error contract");
        reset_all;
        $fclose(output_csv);$fclose(latency_csv);$fclose(stats_csv);$fclose(xof_csv);
        tb_pass=1;
        $display("PASS: V2 Verilog lanes=%0d, 16384 coefficients / 2944 packed words, 64 contexts, abort/restart, output and SHAKE stalls, sticky-error recovery",LANES);
        $finish;
    end
    initial begin #20000000;fail("timeout");end
endmodule
