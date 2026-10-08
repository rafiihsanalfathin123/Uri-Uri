`timescale 1ns/1ps
`ifndef BUFFER_ROWS
`define BUFFER_ROWS 1
`endif
module tb_expanda_buffered;
    localparam ROWS=`BUFFER_ROWS;
    localparam DEPTH=184*ROWS;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,rho_valid=0,start=0,release_buffer=0,read_enable=0;
    reg [127:0] rho_data=0;
    reg [9:0] read_addr=0;
    wire rho_ready,loaded,ready,busy,done,error,valid,read_valid;
    wire [1:0] first_row;
    wire [127:0] read_data;
    reg [255:0] seeds[0:2];
    reg [127:0] expected[0:2207];
    integer job=0,blockno=0,index=0,cycle=0,start_cycle=0,checked=0,publications=0,done_count=0;
    integer csv,checking=0;
    reg tb_pass=0,previous_valid=0;
    reg [1:0] held_row;
    expanda_buffered_top #(.ROWS(ROWS)) dut (.clk(clk),.rst(rst),.rho_data(rho_data),.rho_valid(rho_valid),
        .rho_ready(rho_ready),.rho_loaded(loaded),.expand_a_start(start),.expand_a_ready(ready),
        .expand_a_busy(busy),.expand_a_done(done),.expand_a_error(error),.buffer_valid(valid),
        .buffer_first_row(first_row),.buffer_release(release_buffer),.read_enable(read_enable),
        .read_addr(read_addr),.read_data(read_data),.read_valid(read_valid));
    task fail;input [1023:0] message;begin $display("FAIL: buffered ROWS=%0d %0s",ROWS,message);$finish;end endtask
    always @(posedge clk) begin
        cycle=cycle+1;
        if(checking && start && ready) start_cycle=cycle;
        if(checking && previous_valid && !release_buffer && (!valid || first_row!==held_row)) fail("ownership changed");
        previous_valid=valid && !release_buffer;held_row=first_row;
        #1;
        if(checking && error) fail("internal error");
        if(checking && done) begin
            $fdisplay(csv,"%0d,done,%0d,%0d",job,first_row,cycle-start_cycle);
            done_count=done_count+1;
        end
    end
    initial begin
        $readmemh("vectors/integrated_seeds.hex",seeds);$readmemh("vectors/packed_words.hex",expected);
        if(ROWS==1) csv=$fopen("results/v2_row/latency.csv","w");
        else csv=$fopen("results/v2_full/latency.csv","w");
        if(!csv) fail("result file");
        $fdisplay(csv,"job,event,first_row,cycles_since_start");
        repeat(3) @(negedge clk);rst=0;checking=1;
        for(job=0;job<3;job=job+1) begin
            @(negedge clk);rho_data=seeds[job][127:0];rho_valid=1;
            if(!rho_ready) fail("seed not ready");
            @(negedge clk);rho_data=seeds[job][255:128];
            @(negedge clk);rho_valid=0;
            if(!loaded || !ready) fail("seed not loaded");
            start=1;@(negedge clk);start=0;
            for(blockno=0;blockno<4/ROWS;blockno=blockno+1) begin
                wait(valid);#1;
                if(first_row!==blockno*ROWS) fail("first-row tag");
                $fdisplay(csv,"%0d,published,%0d,%0d",job,first_row,cycle-start_cycle);
                publications=publications+1;
                repeat(11) @(negedge clk);
                // A busy/owned buffer must not load another seed.
                rho_valid=1;start=1;@(negedge clk);rho_valid=0;start=0;
                if(rho_ready || ready) fail("owned buffer allowed new job");
                for(index=0;index<DEPTH;index=index+1) begin
                    if(index%13==0) begin @(negedge clk);read_enable=0;repeat(2) @(negedge clk);end
                    @(negedge clk);read_enable=1;read_addr=index;
                    @(posedge clk);#1;
                    if(!read_valid || read_data!==expected[job*736+blockno*DEPTH+index]) fail("synchronous packed read");
                    checked=checked+1;
                end
                @(negedge clk);read_addr=1023;read_enable=1;
                @(posedge clk);#1;if(read_valid) fail("out-of-range read was valid");
                @(negedge clk);read_enable=0;release_buffer=1;
                @(negedge clk);release_buffer=0;
            end
            wait(!busy && !valid);repeat(3) @(negedge clk);
        end
        if(checked!=2208 || publications!=12/ROWS || done_count!=3) fail("coverage counts");
        $fclose(csv);tb_pass=1;
        $display("PASS: buffered ROWS=%0d, 2208 packed words / 12288 coefficients, 3 matrices, ownership, read latency and bounds",ROWS);$finish;
    end
    initial begin #10000000;fail("timeout");end
endmodule
