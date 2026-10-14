`timescale 1ns/1ps
// Self-checking testbench for dot_product_engine.
//
// Every transaction is compared against a behavioral reference model
// (ref_dot, which is allowed to use '*'). Test groups:
//   1. reset values
//   2. corner cases: zero / maximum operands, single active lanes, carries
//   3. random transactions, some with start/operand noise while busy
//   4. repeated identical transactions
//   5. back-to-back transactions (next start in the same cycle as done)
//   6. in-flight reset at every cycle of a transaction, then recovery
module tb_dot_product_engine;
    localparam W   = 8;
    localparam RW  = 2*W + 2;
    localparam LAT = W + 3;              // start -> done latency in cycles
    localparam [W-1:0] MAX = {W{1'b1}};

    reg            clk   = 1'b0;
    reg            rst_n = 1'b0;
    reg            start = 1'b0;
    reg  [4*W-1:0] a_vec = {4*W{1'b0}};
    reg  [4*W-1:0] b_vec = {4*W{1'b0}};
    wire [RW-1:0]  result;
    wire           busy;
    wire           done;

    dot_product_engine #(.W(W)) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .start (start),
        .a_vec (a_vec),
        .b_vec (b_vec),
        .result(result),
        .busy  (busy),
        .done  (done)
    );

    always #5 clk = ~clk;

    integer errors  = 0;
    integer n_txn   = 0;
    integer n_reset = 0;
    integer seed    = 32'h5EED;
    integer i, k;
    reg [4*W-1:0] ra, rb;

`ifdef DUMP
    initial begin
        $dumpfile("tb_dot_product_engine.vcd");
        $dumpvars(0, tb_dot_product_engine);
    end
`endif

    // ------------------------------------------------------------------
    // Behavioral reference model
    // ------------------------------------------------------------------
    function [RW-1:0] ref_dot(input [4*W-1:0] a, input [4*W-1:0] b);
        integer lane;
        begin
            ref_dot = {RW{1'b0}};
            for (lane = 0; lane < 4; lane = lane + 1)
                ref_dot = ref_dot + a[lane*W +: W] * b[lane*W +: W];
        end
    endfunction

    task fail(input [8*48-1:0] what, input [RW-1:0] got, input [RW-1:0] exp);
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("[%0t] FAIL %0s: got %0d expected %0d", $time, what, got, exp);
        end
    endtask

    // Wait (from the negedge after start) for done; returns cycles waited.
    // With noisy=1, random operands and start pulses are driven while busy.
    task wait_done(input noisy, output integer lat);
        begin
            lat = 0;
            while (done !== 1'b1 && lat < 4 * LAT) begin
                if (noisy) begin
                    start = $random(seed);
                    a_vec = $random(seed);
                    b_vec = $random(seed);
                end
                @(negedge clk);
                lat = lat + 1;
            end
            start = 1'b0;
        end
    endtask

    // One complete transaction; called on a negedge with the engine idle.
    task run_txn(input [4*W-1:0] a, input [4*W-1:0] b, input noisy);
        reg [RW-1:0] expected;
        integer lat;
        begin
            expected = ref_dot(a, b);
            a_vec = a;
            b_vec = b;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            if (busy !== 1'b1) fail("busy not set after start", busy, 1);
            wait_done(noisy, lat);
            n_txn = n_txn + 1;
            if (done !== 1'b1)        fail("timeout waiting for done", 0, 1);
            if (lat != LAT)           fail("latency", lat, LAT);
            if (result !== expected)  fail("result", result, expected);
            if (busy !== 1'b0)        fail("busy high in done cycle", busy, 0);
            @(negedge clk);
            if (done !== 1'b0)        fail("done wider than one cycle", done, 0);
            if (result !== expected)  fail("result not held", result, expected);
        end
    endtask

    // Pack four lane values into an operand vector.
    function [4*W-1:0] pack(input [W-1:0] v3, input [W-1:0] v2,
                            input [W-1:0] v1, input [W-1:0] v0);
        pack = {v3, v2, v1, v0};
    endfunction

    initial begin
        // ---------------- 1. reset values ----------------
        repeat (3) @(negedge clk);
        if (result !== 0 || busy !== 1'b0 || done !== 1'b0)
            fail("reset values", result, 0);
        rst_n = 1'b1;
        @(negedge clk);

        // ---------------- 2. corner cases ----------------
        run_txn(pack(0, 0, 0, 0),           pack(0, 0, 0, 0),           0);
        run_txn(pack(MAX, MAX, MAX, MAX),   pack(MAX, MAX, MAX, MAX),   0);  // max result
        run_txn(pack(MAX, MAX, MAX, MAX),   pack(0, 0, 0, 0),           0);
        run_txn(pack(0, 0, 0, 0),           pack(MAX, MAX, MAX, MAX),   0);
        run_txn(pack(1, 1, 1, 1),           pack(1, 1, 1, 1),           0);
        run_txn(pack(MAX, MAX, MAX, MAX),   pack(1, 1, 1, 1),           0);
        run_txn(pack(8'h80, 8'h80, 8'h80, 8'h80),
                pack(8'h80, 8'h80, 8'h80, 8'h80), 0);                         // carry into bit 16
        run_txn(pack(8'hAA, 8'h55, 8'hAA, 8'h55),
                pack(8'h55, 8'hAA, 8'h55, 8'hAA), 0);
        for (i = 0; i < 4; i = i + 1) begin
            // single active lane, then mismatched lanes (must give zero)
            run_txn({{(3*W){1'b0}}, MAX} << (i*W), {{(3*W){1'b0}}, MAX} << (i*W), 0);
            run_txn({{(3*W){1'b0}}, MAX} << (i*W),
                    {{(3*W){1'b0}}, MAX} << (((i + 1) % 4) * W), 0);
        end
        for (i = 0; i < W; i = i + 1)                                          // powers of two
            run_txn(pack(1 << i, 1 << i, 1 << i, 1 << i), pack(MAX, 1 << i, 1, MAX), 0);

        // ---------------- 3. random (every 4th with noise while busy) ----
        for (i = 0; i < 5000; i = i + 1) begin
            ra = $random(seed);
            rb = $random(seed);
            run_txn(ra, rb, (i % 4) == 0);
        end

        // ---------------- 4. repeated identical transactions -------------
        ra = $random(seed);
        rb = $random(seed);
        for (i = 0; i < 10; i = i + 1)
            run_txn(ra, rb, 0);

        // ---------------- 5. back-to-back --------------------------------
        // The next start is issued in the same cycle done is observed.
        begin : back_to_back
            reg [RW-1:0] expected;
            integer lat;
            ra = $random(seed);
            rb = $random(seed);
            expected = ref_dot(ra, rb);
            a_vec = ra; b_vec = rb; start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            for (i = 0; i < 200; i = i + 1) begin
                wait_done(0, lat);
                n_txn = n_txn + 1;
                if (done !== 1'b1)       fail("b2b timeout", 0, 1);
                if (lat != LAT)          fail("b2b latency", lat, LAT);
                if (result !== expected) fail("b2b result", result, expected);
                // launch the next transaction immediately
                ra = $random(seed);
                rb = $random(seed);
                expected = ref_dot(ra, rb);
                a_vec = ra; b_vec = rb; start = 1'b1;
                @(negedge clk);
                start = 1'b0;
                if (busy !== 1'b1)       fail("b2b start not accepted", busy, 1);
            end
            wait_done(0, lat);
            if (result !== expected)     fail("b2b last result", result, expected);
            @(negedge clk);
        end

        // ---------------- 6. in-flight reset ------------------------------
        // Reset is asserted asynchronously (mid-cycle) k cycles into a
        // transaction, for every k from the start cycle to the done cycle.
        for (k = 0; k <= LAT + 1; k = k + 1) begin
            a_vec = $random(seed); b_vec = $random(seed); start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            repeat (k) @(negedge clk);
            #2 rst_n = 1'b0;
            n_reset = n_reset + 1;
            #1;
            if (result !== 0)   fail("in-flight reset: result not cleared", result, 0);
            if (busy !== 1'b0)  fail("in-flight reset: busy not cleared", busy, 0);
            if (done !== 1'b0)  fail("in-flight reset: done not cleared", done, 0);
            @(negedge clk);
            rst_n = 1'b1;
            // no stale done / busy may appear after reset
            repeat (2 * LAT) begin
                @(negedge clk);
                if (done !== 1'b0) fail("stale done after reset", done, 0);
                if (busy !== 1'b0) fail("stale busy after reset", busy, 0);
            end
            // the engine must work normally afterwards
            ra = $random(seed);
            rb = $random(seed);
            run_txn(ra, rb, 0);
        end

        $display("--------------------------------------------------");
        $display("dot_product_engine: %0d transactions, %0d in-flight resets, %0d errors",
                 n_txn, n_reset, errors);
        $display("latency start->done = %0d cycles", LAT);
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED");
        $finish;
    end

    initial begin
        #20_000_000;
        $display("TIMEOUT: simulation watchdog expired");
        $display("TESTS FAILED");
        $finish;
    end
endmodule
