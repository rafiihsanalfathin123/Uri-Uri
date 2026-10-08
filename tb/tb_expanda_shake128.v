`timescale 1ns/1ps
`ifndef SHAKE_LANES
`define SHAKE_LANES 5
`endif
// Adapted from the supplied MIT SHAKE regression; original preserved.
module tb_expanda_shake128;
    reg tb_pass=0;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, shake_init = 0, shake_absorb_en = 0;
    reg shake_finalize = 0, shake_squeeze_en = 0;
    reg [127:0] shake_in_data = 0;
    reg shake_in_valid = 0;
    reg [4:0] shake_in_nbytes = 0;
    wire shake_in_ready;
    wire [127:0] shake_out_data;
    wire shake_out_valid;
    reg shake_out_ready = 0;
    wire shake_ready, shake_phase_done, shake_error;

    expanda_shake128 #(.PARALLEL_LANES(`SHAKE_LANES)) dut (
        .clk(clk), .rst(rst), .shake_init(shake_init),
        .shake_absorb_en(shake_absorb_en), .shake_finalize(shake_finalize),
        .shake_squeeze_en(shake_squeeze_en), .shake_in_data(shake_in_data),
        .shake_in_valid(shake_in_valid), .shake_in_nbytes(shake_in_nbytes),
        .shake_in_ready(shake_in_ready), .shake_out_data(shake_out_data),
        .shake_out_valid(shake_out_valid), .shake_out_ready(shake_out_ready),
        .shake_ready(shake_ready), .shake_phase_done(shake_phase_done),
        .shake_error(shake_error)
    );

    reg [7:0] message [0:4095];
    reg [7:0] expected [0:4095];
    integer fd, scanned, case_count, case_id, input_len, output_len;
    integer same_beat, pauses, c, i, j, offset, n, produced, ticks;
    integer total_cycles = 0;
    reg request_pending;
    reg stalled = 0;
    reg [127:0] stalled_word;
    reg [1023:0] vector_path;

    // Check output stability independently from the byte scoreboard.
    always @(posedge clk) begin
        total_cycles <= total_cycles + 1;
        if (rst || shake_init) begin
            stalled <= 0;
        end else begin
            if (stalled && (!shake_out_valid || shake_out_data !== stalled_word))
                begin $display("FAIL: Output changed while stalled"); $finish; end
            stalled <= shake_out_valid && !shake_out_ready;
            stalled_word <= shake_out_data;
        end
    end

    initial begin
        #100000000;
        begin $display("FAIL: Global simulation timeout"); $finish; end
    end

    task init_job;
        begin
            @(negedge clk);
            shake_in_valid = 0;
            shake_finalize = 0;
            shake_squeeze_en = 0;
            shake_out_ready = 0;
            shake_absorb_en = 1;
            shake_init = 1;
            @(negedge clk);
            shake_init = 0;
            if (shake_error || !shake_phase_done)
                begin $display("FAIL: Initialization did not clear error/report completion"); $finish; end
        end
    endtask

    task invalid_nbytes;
        input [4:0] count;
        begin
            init_job;
            shake_in_nbytes = count;
            shake_in_valid = 1;
            @(negedge clk);
            shake_in_valid = 0;
            if (!shake_error || shake_in_ready || shake_out_valid)
                begin $display("FAIL: Invalid nbytes not rejected: %0d", count); $finish; end
            repeat (3) @(negedge clk);
            if (!shake_error) begin $display("FAIL: Error was not sticky"); $finish; end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        // finalize without initialization must not silently hash stale data.
        shake_finalize = 1;
        @(negedge clk);
        shake_finalize = 0;
        if (!shake_error) begin $display("FAIL: Finalize before init not rejected"); $finish; end
        invalid_nbytes(0);
        invalid_nbytes(17);
        invalid_nbytes(31);

        // Exercise synchronous reset/init abortion during a permutation.
        init_job;
        shake_in_nbytes = 16;
        shake_in_data = 128'h00112233445566778899aabbccddeeff;
        shake_in_valid = 1;
        shake_finalize = 1;
        @(negedge clk);
        shake_in_valid = 0;
        shake_finalize = 0;
        repeat (20) @(negedge clk);
        init_job;

        if (!$value$plusargs("VECTORS=%s", vector_path))
            vector_path = "tests/vectors.txt";
        fd = $fopen(vector_path, "r");
        if (!fd) begin $display("FAIL: Cannot open golden vector file"); $finish; end
        scanned = $fscanf(fd, "%d", case_count);
        if (scanned != 1) begin $display("FAIL: Invalid vector header"); $finish; end

        for (c = 0; c < case_count; c = c + 1) begin
            scanned = $fscanf(fd, "%d %d %d %d %d", case_id, input_len,
                              output_len, same_beat, pauses);
            if (scanned != 5) begin $display("FAIL: Invalid case header"); $finish; end
            for (i = 0; i < input_len; i = i + 1) begin
                scanned = $fscanf(fd, "%h", message[i]);
                if (scanned != 1) begin $display("FAIL: Missing input byte"); $finish; end
            end
            for (i = 0; i < output_len; i = i + 1) begin
                scanned = $fscanf(fd, "%h", expected[i]);
                if (scanned != 1) begin $display("FAIL: Missing expected byte"); $finish; end
            end

            init_job;
            offset = 0;
            while (offset < input_len) begin
                if (pauses) begin
                    shake_absorb_en = 0;
                    repeat ((offset / 16) % 3 + 1) @(negedge clk);
                    if (shake_in_ready)
                        begin $display("FAIL: Input ready asserted with absorb disabled"); $finish; end
                    shake_absorb_en = 1;
                end
                while (!shake_in_ready) @(negedge clk);
                n = (input_len - offset > 16) ? 16 : input_len - offset;
                // Deliberately poison invalid upper bytes on a short beat.
                shake_in_data = {128{1'b1}};
                for (j = 0; j < n; j = j + 1)
                    shake_in_data[j*8 +: 8] = message[offset+j];
                shake_in_nbytes = n;
                shake_in_valid = 1;
                shake_finalize = same_beat && (offset + n == input_len);
                @(posedge clk);
                if (!shake_in_ready) begin $display("FAIL: Input handshake unexpectedly lost"); $finish; end
                @(negedge clk);
                shake_in_valid = 0;
                shake_finalize = 0;
                offset = offset + n;
            end

            if (!same_beat || input_len == 0) begin
                shake_finalize = 1;
                @(negedge clk);
                shake_finalize = 0;
            end
            ticks = 0;
            while (!shake_phase_done) begin
                @(negedge clk);
                ticks = ticks + 1;
                if (shake_error || ticks > 100000)
                    begin $display("FAIL: Finalize failed/timed out on case %0d", case_id); $finish; end
            end
            if (!shake_ready || shake_in_ready)
                begin $display("FAIL: Unexpected post-finalize status"); $finish; end

            produced = 0;
            ticks = 0;
            request_pending = 0;
            while (produced < output_len) begin
                // Half the jobs request one word at a time; half stream.
                if (pauses) begin
                    shake_squeeze_en = !request_pending && shake_ready;
                    if (shake_squeeze_en) request_pending = 1;
                    shake_out_ready = ((ticks % 11) >= 4);
                end else begin
                    shake_squeeze_en = 1;
                    shake_out_ready = 1;
                end
                @(posedge clk);
                if (shake_out_valid && shake_out_ready) begin
                    for (j = 0; j < 16; j = j + 1) begin
                        if (shake_out_data[j*8 +: 8] !== expected[produced+j])
                            begin $display("FAIL: Case %0d byte %0d: got %02x expected %02x",
                                   case_id, produced+j,
                                   shake_out_data[j*8 +: 8], expected[produced+j]); $finish; end
                    end
                    produced = produced + 16;
                    request_pending = 0;
                end
                @(negedge clk);
                ticks = ticks + 1;
                if (shake_error || ticks > 100000)
                    begin $display("FAIL: Squeeze failed/timed out on case %0d", case_id); $finish; end
            end
            shake_squeeze_en = 0;
            shake_out_ready = 0;
            repeat (3) @(negedge clk);
            if (shake_out_valid)
                begin $display("FAIL: Unrequested extra output word"); $finish; end
            $display("PASS case=%0d input=%0d output=%0d pauses=%0d",
                     case_id, input_len, output_len, pauses);
        end
        $fclose(fd);
        tb_pass=1;
        $display("PASS ALL %0d golden vectors; cycles=%0d", case_count, total_cycles);
        $finish;
    end
endmodule
