`timescale 1ns/1ps
// Single-channel post-SHAKE comparison; upstream source stays unmodified.
module tb_expanda_benchmark;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,start=0;
    reg [7:0] stream [0:38399];
    reg [22:0] expected [0:8191];
    reg [63:0] old_data=0,new_data=0;
    reg old_valid=0,new_valid=0;
    wire old_ready,old_outvalid,new_ready,new_outvalid,new_last,new_busy,new_done;
    wire [91:0] old_coeff;
    wire [22:0] new_coeff;
    wire [7:0] new_byte;
    wire new_bytevalid,new_byteready;
    integer old_cursor=0,new_cursor=0,old_count=0,new_count=0;
    integer cycle=0,start_cycle=0,old_cycles=0,new_cycles=0;
    integer poly=0,b,base,idx,fd,total_old=0,total_new=0;
    reg take_oldword,take_newword;
    rejection_a baseline (.rst(rst),.clk(clk),.valid_i(old_valid),.ready_i(old_ready),
        .rdi(old_data),.samples(old_coeff),.valid_o(old_outvalid),.ready_o(1'b1));
    expanda_word_to_byte #(.MSB_FIRST(0)) adapter (
        .clk(clk),.rst(rst),.flush(new_done),.word_data(new_data),.word_valid(new_valid),
        .word_ready(new_ready),.byte_data(new_byte),.byte_valid(new_bytevalid),.byte_ready(new_byteready));
    expanda_rejection_sampler candidate (
        .clk(clk),.rst(rst),.start(start),.byte_data(new_byte),.byte_valid(new_bytevalid),
        .byte_ready(new_byteready),.coeff_data(new_coeff),.coeff_valid(new_outvalid),
        .coeff_ready(1'b1),.coeff_last(new_last),.busy(new_busy),.done(new_done));
    // Saturated precomputed XOF: no SHAKE cost, no output stalls. Upstream
    // input valid pulses only when ready, matching an accepted-word producer.
    always @(negedge clk) begin
        old_valid=0;new_valid=0;
        if(!rst) begin
            if(old_count<256 && old_ready) begin
                for(b=0;b<8;b=b+1) old_data[b*8+:8]=stream[base+old_cursor+b];
                old_valid=1;
            end
            if(new_count<256 && new_ready) begin
                for(b=0;b<8;b=b+1) new_data[b*8+:8]=stream[base+new_cursor+b];
                new_valid=1;
            end
        end
    end
    always @(posedge clk) begin
        cycle=cycle+1;
        take_oldword=old_valid && old_ready;
        take_newword=new_valid && new_ready;
        if(!rst) begin
            if(old_outvalid && old_count<256) begin
                for(idx=0;idx<4;idx=idx+1)
                    if(old_coeff[idx*23+:23] !== expected[4096+poly*256+old_count+idx])
                        begin $display("FAIL: baseline mismatch poly=%0d coeff=%0d",poly,old_count+idx); $finish; end
                old_count=old_count+4;
                if(old_count==256) old_cycles=cycle-start_cycle;
            end
            if(new_outvalid && new_count<256) begin
                if(new_coeff !== expected[4096+poly*256+new_count])
                    begin $display("FAIL: new sampler mismatch poly=%0d coeff=%0d",poly,new_count); $finish; end
                new_count=new_count+1;
                if(new_count==256) new_cycles=cycle-start_cycle;
            end
        end
        #1;
        if(!rst) begin
            if(take_oldword) old_cursor=old_cursor+8;
            if(take_newword) new_cursor=new_cursor+8;
        end
    end
    initial begin
        $dumpfile("results/expanda_benchmark.vcd");$dumpvars(0,tb_expanda_benchmark);
        $readmemh("vectors/expanda_bytes.hex",stream);
        $readmemh("vectors/expanda_coeffs.hex",expected);
        fd=$fopen("results/expanda_benchmark.csv","w");
        $fdisplay(fd,"row,col,baseline_cycles,new_cycles,baseline_input_bytes,new_input_bytes");
        for(poly=0;poly<16;poly=poly+1) begin
            rst=1; repeat(3) @(negedge clk);
            old_cursor=0;new_cursor=0;old_count=0;new_count=0;old_cycles=0;new_cycles=0;
            base=(16+poly)*1200;
            // Drive reset release away from the stimulus driver's edge.
            #1;rst=0;start=1;start_cycle=cycle;
            @(negedge clk);#1;start=0;
            wait(old_count==256 && new_count==256);
            @(negedge clk);#1;
            total_old=total_old+old_cycles;total_new=total_new+new_cycles;
            $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d",poly/4,poly%4,old_cycles,new_cycles,old_cursor,new_cursor);
        end
        $fclose(fd);
        $display("PASS: both samplers match 4096 SHAKE-derived coefficients.");
        $display("SAMPLER_ONLY: upstream total=%0d cycles; new plus serializer total=%0d cycles (16 sequential polynomials).",total_old,total_new);
        $finish;
    end
    initial begin #2000000;begin $display("FAIL: benchmark timeout"); $finish; end end
endmodule
