`timescale 1ns/1ps
module tb_expanda_sampler;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,start=0,byte_valid=0,coeff_ready=0;
    reg [7:0] byte_data=0;
    wire byte_ready,coeff_valid,coeff_last,busy,done;
    wire [22:0] coeff;
    reg [7:0] stream [0:38399];
    reg [22:0] expected [0:8191];
    integer tick=0,cursor=0,count=0,done_count=0,stalls=0;
    reg checking=0, take_byte,take_coeff,take_done,prev_stall=0;
    reg [22:0] held_coeff;
    reg held_last;
    expanda_rejection_sampler dut (
        .clk(clk),.rst(rst),.start(start),.byte_data(byte_data),
        .byte_valid(byte_valid),.byte_ready(byte_ready),.coeff_data(coeff),
        .coeff_valid(coeff_valid),.coeff_ready(coeff_ready),.coeff_last(coeff_last),
        .busy(busy),.done(done)
    );
    always @(negedge clk) begin
        tick=tick+1;
        coeff_ready=checking && (tick%19>=9);
        if(checking && busy && !byte_valid && tick%7!=0) begin
            byte_data=stream[cursor];byte_valid=1;
        end
    end
    always @(posedge clk) begin
        take_byte=byte_valid && byte_ready;
        take_coeff=coeff_valid && coeff_ready;
        take_done=done;
        if(checking && !rst) begin
            if(prev_stall && (!coeff_valid || coeff!==held_coeff || coeff_last!==held_last))
                begin $display("FAIL: output changed while stalled"); $finish; end
            prev_stall=coeff_valid && !coeff_ready;
            if(prev_stall) begin held_coeff=coeff;held_last=coeff_last;stalls=stalls+1;end
            if(take_coeff) begin
                if(count>=256 || coeff!==expected[count]) begin $display("FAIL: sampler coefficient mismatch %0d",count); $finish; end
                if(coeff_last !== (count==255)) begin $display("FAIL: wrong coeff_last"); $finish; end
                count=count+1;
            end
            if(take_done) done_count=done_count+1;
        end
        #1;
        if(checking && take_byte) begin cursor=cursor+1;byte_valid=0;end
    end
    initial begin
        $dumpfile("results/expanda_sampler.vcd");
        $dumpvars(0,tb_expanda_sampler);
        $readmemh("vectors/expanda_bytes.hex",stream);
        $readmemh("vectors/expanda_coeffs.hex",expected);
        repeat(3) @(negedge clk);rst=0;start=1;
        @(negedge clk);start=0;byte_valid=1;byte_data=8'hfe;
        @(negedge clk);byte_valid=0;
        // Abort a partial three-byte candidate, then start a fresh polynomial.
        @(negedge clk);rst=1;
        @(negedge clk);rst=0;checking=1;start=1;
        @(negedge clk);start=0;
        wait(done);repeat(3) @(negedge clk);
        if(count!=256 || done_count!=1 || stalls==0 || busy || coeff_valid || byte_ready)
            begin $display("FAIL: bad final sampler state"); $finish; end
        $display("PASS: sampler reset, rejection boundaries, output stability through %0d stall cycles, exact 256 termination.",stalls);
        $finish;
    end
    initial begin #500000;begin $display("FAIL: sampler timeout"); $finish; end end
endmodule
