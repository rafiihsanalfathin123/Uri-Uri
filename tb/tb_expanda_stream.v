`timescale 1ns/1ps
module tb_expanda_stream;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, job_valid=0;
    wire job_ready, request_valid, byte_ready, cancel, row_valid, read_valid, busy, done;
    reg request_ready=0, byte_valid=0, release_row=0, read_enable=0;
    reg [7:0] byte_data=0, read_addr=0;
    reg [63:0] word_data=0;
    integer byte_lane;
    reg [255:0] rho=0;
    wire [255:0] req_rho;
    wire [1:0] req_row, req_col, row_index;
    wire [95:0] read_data;
    reg [7:0] stream [0:38399];
    reg [22:0] expected [0:8191];
    integer job, row, wordno, lane, base, k, cursor=0, polynomial=0;
    integer tick=0, checked=0, requests=0, cancels=0, done_count=0;
    reg sending=0;
    reg take_request, take_byte, take_cancel, take_done;
`ifdef SHAKE64
    expanda_shake64_top #(.MSB_FIRST(`BYTE_MSB_FIRST)) dut (
`else
    expanda_stream_top dut (
`endif
        .clk(clk), .rst(rst), .job_valid(job_valid), .job_ready(job_ready), .rho(rho),
        .xof_request_valid(request_valid), .xof_request_ready(request_ready),
        .xof_rho(req_rho), .xof_row(req_row), .xof_col(req_col),
`ifdef SHAKE64
        .shake_word_data(word_data), .shake_word_valid(byte_valid), .shake_word_ready(byte_ready),
        .osh_dst_ready(),
`else
        .xof_byte_data(byte_data), .xof_byte_valid(byte_valid), .xof_byte_ready(byte_ready),
`endif
        .xof_cancel(cancel), .row_valid(row_valid), .row_index(row_index),
        .row_release(release_row), .row_read_enable(read_enable), .row_read_addr(read_addr),
        .row_read_data(read_data), .row_read_valid(read_valid), .busy(busy), .job_done(done)
    );
    // SHAKE stand-in: delays request acceptance and inserts byte gaps. Valid is
    // held with stable data until accepted, even if the sampler is not ready.
    always @(negedge clk) begin
        tick=tick+1;
        if (rst) begin request_ready=0; byte_valid=0; end
        else begin
            request_ready = !sending && (tick % 5 != 0);
            if (sending && !byte_valid && tick % 7 != 0) begin
                byte_data=stream[polynomial*1200+cursor]; byte_valid=1;
`ifdef SHAKE64
                for(byte_lane=0;byte_lane<8;byte_lane=byte_lane+1)
                    if (`BYTE_MSB_FIRST)
                        word_data[63-byte_lane*8 -: 8]=stream[polynomial*1200+cursor+byte_lane];
                    else word_data[byte_lane*8 +: 8]=stream[polynomial*1200+cursor+byte_lane];
`endif
            end
            if (!sending) byte_valid=0;
        end
    end
    always @(posedge clk) begin
        take_request=request_valid && request_ready;
        take_byte=byte_valid && byte_ready;
        take_cancel=cancel;
        take_done=done;
        #1;
        if (!rst) begin
            if (take_request) begin
                if ({req_row,req_col} !== (requests % 16))
                    begin $display("FAIL: wrong polynomial context"); $finish; end
                if (req_rho !== rho) begin $display("FAIL: rho mismatch"); $finish; end
                polynomial=requests; requests=requests+1; cursor=0; sending=1;
            end
            if (take_byte) begin
`ifdef SHAKE64
                cursor=cursor+8;
`else
                cursor=cursor+1;
`endif
                byte_valid=0;
                if (cursor >= 1200) begin $display("FAIL: stream exhausted"); $finish; end
            end
            if (take_cancel) begin sending=0; byte_valid=0; cancels=cancels+1; end
            if (take_done) done_count=done_count+1;
        end
    end
    initial begin
`ifdef SHAKE64
        if (`BYTE_MSB_FIRST) $dumpfile("results/expanda_shake64_msb.vcd");
        else $dumpfile("results/expanda_shake64_lsb.vcd");
`else
        $dumpfile("results/expanda_stream.vcd");
`endif
        $dumpvars(0,tb_expanda_stream);
        $readmemh("vectors/expanda_bytes.hex",stream);
        $readmemh("vectors/expanda_coeffs.hex",expected);
        repeat(4) @(negedge clk); rst=0;
        for(job=0;job<2;job=job+1) begin
            for(k=0;k<32;k=k+1) rho[k*8+:8]=k;
            @(negedge clk); job_valid=1;
            @(negedge clk); job_valid=0;
            for(row=0;row<4;row=row+1) begin
                wait(row_valid);
                if(row_index !== row) begin $display("FAIL: wrong result row"); $finish; end
                // Hold the full row to test producer pause and slot retention.
                repeat(13) begin
                    @(negedge clk);
                    if(request_valid || byte_ready || !row_valid)
                        begin $display("FAIL: producer advanced before release"); $finish; end
                end
                for(wordno=0;wordno<256;wordno=wordno+1) begin
                    @(negedge clk); read_enable=1; read_addr=wordno;
                    @(posedge clk); #1;
                    if(!read_valid) begin $display("FAIL: missing synchronous read response"); $finish; end
                    base=job*4096+row*1024+wordno*4;
                    for(lane=0;lane<4;lane=lane+1) begin
                        if(read_data[lane*24+:24] !== {1'b0,expected[base+lane]})
                            begin $display("FAIL: coefficient mismatch job=%0d row=%0d word=%0d lane=%0d got=%h expected=%h",
                                job,row,wordno,lane,read_data[lane*24+:24],expected[base+lane]); $finish; end
                        checked=checked+1;
                    end
                end
                @(negedge clk); read_enable=0;
                @(posedge clk); #1;
                if(read_valid) begin $display("FAIL: read_valid did not clear"); $finish; end
                @(negedge clk); release_row=1;
                @(negedge clk); release_row=0;
            end
            wait(job_ready);
            repeat(2) @(negedge clk);
        end
        if(requests!=32 || cancels!=32 || done_count!=2 || checked!=8192)
            begin $display("FAIL: incorrect lifecycle counts %0d %0d %0d %0d",requests,cancels,done_count,checked); $finish; end
        $display("PASS: 8192 coefficients, 32 contexts, eight row lifetimes, two jobs.");
        $finish;
    end
    initial begin #2000000; begin $display("FAIL: timeout"); $finish; end end
endmodule
