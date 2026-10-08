`timescale 1ns/1ps
module tb_expanda_integrated;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,job_valid=0,release_row=0,read_enable=0;
    reg [255:0] rho=0;
    reg [7:0] read_addr=0;
    wire job_ready,row_valid,read_valid,busy,done,error;
    wire [1:0] row_index;
    wire [95:0] read_data;
    reg [255:0] seeds[0:2];
    reg [22:0] expected[0:12287];
    reg [7:0] xof[0:57599];
    integer job,row,wordno,lane,base,byte_idx,poly_number=0;
    integer checked=0,requests=0,cancels=0,done_count=0,absorbed=0,out_bytes=0;
    integer cycle=0,start_cycle=0,row_start_cycle=0,csv;
    integer comparison_csv,xof_csv,stats_csv;
    integer sampler_bytes=0,poly_coefficients=0,permutation_cycles=0,permutations=0;
    reg checking=0,prev_word_stall=0,prev_row_hold=0;
    reg [127:0] held_word;
    reg [127:0] expected_xof_word;
    reg [1:0] held_row;
    reg [7:0] expected_byte;
    expanda_integrated_top dut (
        .clk(clk),.rst(rst),.job_valid(job_valid),.job_ready(job_ready),.rho(rho),
        .row_valid(row_valid),.row_index(row_index),.row_release(release_row),
        .row_read_enable(read_enable),.row_read_addr(read_addr),.row_read_data(read_data),
        .row_read_valid(read_valid),.busy(busy),.job_done(done),.job_error(error)
    );
    always @(posedge clk) begin
        cycle=cycle+1;
        if(rst) begin prev_word_stall=0;prev_row_hold=0;end
        else if(checking) begin
            if(error) begin $display("FAIL: integrated SHAKE error"); $finish; end
            if(prev_word_stall && !dut.shake_init &&
                (!dut.shake_out_valid || dut.shake_out_data!==held_word))
                begin $display("FAIL: SHAKE word changed under backpressure"); $finish; end
            prev_word_stall=dut.shake_out_valid && !dut.shake_out_ready && !dut.shake_init;
            held_word=dut.shake_out_data;
            if(prev_row_hold && (!row_valid || row_index!==held_row))
                begin $display("FAIL: published row changed before release"); $finish; end
            prev_row_hold=row_valid && !release_row;
            held_row=row_index;
            if(dut.req_valid && dut.req_ready) begin
                if({dut.req_row,dut.req_col} !== (requests%16)) begin $display("FAIL: wrong context order"); $finish; end
                poly_number=requests;requests=requests+1;absorbed=0;out_bytes=0;
                sampler_bytes=0;poly_coefficients=0;permutation_cycles=0;permutations=0;
            end
            if(dut.byte_valid && dut.byte_ready) sampler_bytes=sampler_bytes+1;
            if(dut.core.coeff_valid && dut.core.coeff_ready) poly_coefficients=poly_coefficients+1;
            if(dut.shake.fsm>=4 && dut.shake.fsm<=11) permutation_cycles=permutation_cycles+1;
            if(dut.shake.fsm==4) permutations=permutations+1;
            if(dut.shake_in_valid && dut.shake_in_ready) begin
                if(dut.shake_in_nbytes !== ((absorbed==32)?5'd2:5'd16)) begin $display("FAIL: wrong absorb nbytes"); $finish; end
                for(byte_idx=0;byte_idx<dut.shake_in_nbytes;byte_idx=byte_idx+1) begin
                    if(absorbed+byte_idx<32) expected_byte=seeds[job][(absorbed+byte_idx)*8+:8];
                    else if(absorbed+byte_idx==32) expected_byte={6'd0,dut.req_col};
                    else expected_byte={6'd0,dut.req_row};
                    if(dut.shake_in_data[byte_idx*8+:8] !== expected_byte)
                        begin $display("FAIL: absorb data mismatch byte %0d",absorbed+byte_idx); $finish; end
                end
                absorbed=absorbed+dut.shake_in_nbytes;
            end
            if(dut.shake_finalize && absorbed!=34) begin $display("FAIL: finalize before 34 bytes"); $finish; end
            if(dut.shake_out_valid && dut.shake_out_ready) begin
                for(byte_idx=0;byte_idx<16;byte_idx=byte_idx+1) begin
                    expected_xof_word[byte_idx*8+:8]=xof[poly_number*1200+out_bytes+byte_idx];
                    if(dut.shake_out_data[byte_idx*8+:8] !== xof[poly_number*1200+out_bytes+byte_idx])
                        begin $display("FAIL: live SHAKE mismatch poly=%0d byte=%0d",poly_number,out_bytes+byte_idx); $finish; end
                end
                $fdisplay(xof_csv,"%0d,%0d,%0d,%0d,%032h,%032h,%0d",poly_number/16,
                    (poly_number%16)/4,poly_number%4,out_bytes,expected_xof_word,dut.shake_out_data,
                    expected_xof_word===dut.shake_out_data);
                out_bytes=out_bytes+16;
            end
            if(dut.cancel) begin
                if(absorbed!=34 || out_bytes<768) begin $display("FAIL: premature polynomial completion"); $finish; end
                if(poly_coefficients!=256 || sampler_bytes%3!=0)
                    begin $display("FAIL: polynomial statistics disagree with completion"); $finish; end
                $fdisplay(stats_csv,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",poly_number/16,
                    (poly_number%16)/4,poly_number%4,absorbed,out_bytes,sampler_bytes,
                    poly_coefficients,sampler_bytes/3-poly_coefficients,permutations,permutation_cycles);
                cancels=cancels+1;
            end
            if(done) done_count=done_count+1;
        end
    end
    initial begin
        // Record interfaces and control, without dumping the 1600-bit state on
        // every lane update. Complete live-SHAKE output is still observable.
        $dumpfile("results/expanda_integrated.vcd");
        $dumpvars(1,tb_expanda_integrated);
        $dumpvars(0,dut.ctrl_state,dut.input_word,dut.req_valid,dut.req_ready,dut.req_row,dut.req_col,
            dut.shake_init,dut.shake_finalize,dut.shake_phase_done,dut.shake_in_valid,dut.shake_in_ready,
            dut.shake_in_data,dut.shake_in_nbytes,dut.shake_out_data,dut.shake_out_valid,dut.shake_out_ready,
            dut.shake_squeeze_en,dut.cancel,dut.shake.fsm,dut.shake.byte_pos,dut.core.coeff,dut.core.coeff_valid);
        $readmemh("vectors/integrated_seeds.hex",seeds);
        $readmemh("vectors/integrated_coeffs.hex",expected);
        $readmemh("vectors/integrated_xof.hex",xof);
        repeat(4) @(negedge clk);rst=0;
        // Reset while the actual SHAKE engine is permuting a partial job.
        rho=256'hdeadbeef;job_valid=1;
        @(negedge clk);job_valid=0;
        repeat(100) @(negedge clk);
        if(dut.shake.fsm<4 || dut.shake.fsm>11) begin $display("FAIL: abort stimulus missed permutation"); $finish; end
        rst=1;repeat(3) @(negedge clk);rst=0;
        checking=1;
        csv=$fopen("results/expanda_integrated_cycles.csv","w");
        comparison_csv=$fopen("results/expanda_output_comparison.csv","w");
        xof_csv=$fopen("results/expanda_xof_comparison.csv","w");
        stats_csv=$fopen("results/expanda_polynomial_stats.csv","w");
        if(!csv || !comparison_csv || !xof_csv || !stats_csv) begin $display("FAIL: could not open result files"); $finish; end
        $fdisplay(csv,"job,row,generation_cycles,cycles_since_job_start");
        $fdisplay(comparison_csv,"job,row,col,coefficient,expected_hex,actual_hex,match");
        $fdisplay(xof_csv,"job,row,col,byte_offset,expected_word_hex,actual_word_hex,match");
        $fdisplay(stats_csv,"job,row,col,absorb_bytes,xof_transfer_bytes,sampler_bytes,accepted_coefficients,rejected_candidates,permutations,permutation_cycles");
        for(job=0;job<3;job=job+1) begin
            @(negedge clk);rho=seeds[job];job_valid=1;start_cycle=cycle;row_start_cycle=cycle;
            @(negedge clk);job_valid=0;
            // Change external rho after acceptance: internal seed must be latched.
            rho=~rho;
            for(row=0;row<4;row=row+1) begin
                wait(row_valid);
                if(row_index!==row) begin $display("FAIL: wrong published row"); $finish; end
                $fdisplay(csv,"%0d,%0d,%0d,%0d",job,row,cycle-row_start_cycle,cycle-start_cycle);
                repeat(17) @(negedge clk);
                if(dut.req_valid || dut.byte_ready) begin $display("FAIL: producer advanced during row hold"); $finish; end
                // Busy requests must not replace the active seed or create jobs.
                job_valid=1;@(negedge clk);job_valid=0;
                for(wordno=0;wordno<256;wordno=wordno+1) begin
                    if(wordno%11==0) begin
                        @(negedge clk);read_enable=0;
                        repeat(2) @(negedge clk);
                    end
                    @(negedge clk);read_enable=1;read_addr=wordno;
                    @(posedge clk);#1;
                    if(!read_valid) begin $display("FAIL: missing synchronous read"); $finish; end
                    base=job*4096+row*1024+wordno*4;
                    for(lane=0;lane<4;lane=lane+1) begin
                        $fdisplay(comparison_csv,"%0d,%0d,%0d,%0d,%06h,%06h,%0d",job,row,
                            wordno/64,(wordno%64)*4+lane,{1'b0,expected[base+lane]},read_data[lane*24+:24],
                            read_data[lane*24+:24]==={1'b0,expected[base+lane]});
                        if(read_data[lane*24+:24] !== {1'b0,expected[base+lane]})
                            begin $display("FAIL: matrix mismatch job=%0d row=%0d word=%0d lane=%0d",job,row,wordno,lane); $finish; end
                        checked=checked+1;
                    end
                end
                @(negedge clk);read_enable=0;
                @(posedge clk);#1;
                if(read_valid) begin $display("FAIL: read_valid failed to clear"); $finish; end
                @(negedge clk);release_row=1;row_start_cycle=cycle;
                @(negedge clk);release_row=0;
            end
            wait(job_ready);repeat(3) @(negedge clk);
        end
        $fclose(csv);
        $fclose(comparison_csv);$fclose(xof_csv);$fclose(stats_csv);
        if(checked!=12288 || requests!=48 || cancels!=48 || done_count!=3)
            begin $display("FAIL: lifecycle count mismatch"); $finish; end
        checking=0;
        @(negedge clk);rho=seeds[0];job_valid=1;
        @(negedge clk);job_valid=0;
        repeat(100) @(negedge clk);
        // Deliberate simulation fault injection tests the public error contract.
        force dut.shake.shake_error=1'b1;
        repeat(2) @(negedge clk);
        release dut.shake.shake_error;
        repeat(3) @(negedge clk);
        if(!error || job_ready || row_valid || read_valid || busy || done)
            begin $display("FAIL: internal SHAKE error did not abort and latch"); $finish; end
        job_valid=1;repeat(3) @(negedge clk);job_valid=0;
        if(!error || job_ready) begin $display("FAIL: error accepted a job without reset"); $finish; end
        rst=1;repeat(3) @(negedge clk);rst=0;
        @(negedge clk);
        if(error || !job_ready) begin $display("FAIL: error reset recovery failed"); $finish; end
        $display("PASS: LIVE SHAKE128 integration, 12288 coefficients, 48 contexts, 3 seeds, 12 row lifetimes, abort/restart, sticky-error recovery, 34-byte absorb and XOF byte scoreboards.");
        $finish;
    end
    initial begin #20000000;begin $display("FAIL: integrated timeout"); $finish; end end
endmodule
