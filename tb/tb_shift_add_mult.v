`timescale 1ns/1ps
// Exhaustive self-checking testbench for shift_add_mult.
// Every one of the 2^W x 2^W operand pairs is multiplied and compared with
// the behavioral product. While the unit is busy the testbench drives random
// operands and random start pulses, which must all be ignored.
module tb_shift_add_mult;
    localparam W   = 8;
    localparam LAT = W;                  // start -> done latency in cycles

    reg            clk   = 1'b0;
    reg            rst_n = 1'b0;
    reg            start = 1'b0;
    reg  [W-1:0]   mcand = {W{1'b0}};
    reg  [W-1:0]   mplier = {W{1'b0}};
    wire [2*W-1:0] product;
    wire           busy;
    wire           done;

    shift_add_mult #(.W(W)) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .multiplicand(mcand),
        .multiplier  (mplier),
        .product     (product),
        .busy        (busy),
        .done        (done)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer seed   = 7;
    integer x, y, lat;

`ifdef DUMP
    initial begin
        $dumpfile("tb_shift_add_mult.vcd");
        $dumpvars(0, tb_shift_add_mult);
    end
`endif

    task fail(input [8*48-1:0] what);
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("[%0t] FAIL %0s  (a=%0d b=%0d product=%0d)",
                         $time, what, x, y, product);
        end
    endtask

    // multiply x*y and check; called on a negedge with the unit idle
    task run_mult(input [W-1:0] a, input [W-1:0] b);
        reg [2*W-1:0] expected;
        begin
            expected = a * b;            // behavioral reference
            mcand  = a;
            mplier = b;
            start  = 1'b1;
            @(negedge clk);
            lat = 0;
            if (busy !== 1'b1) fail("busy not set after start");
            // noise while busy: must be ignored
            while (done !== 1'b1 && lat < 4 * LAT) begin
                start  = $random(seed);
                mcand  = $random(seed);
                mplier = $random(seed);
                @(negedge clk);
                lat = lat + 1;
            end
            start = 1'b0;
            checks = checks + 1;
            if (done !== 1'b1)          fail("timeout waiting for done");
            if (lat != LAT)             fail("wrong latency");
            if (product !== expected)   fail("wrong product");
            if (busy !== 1'b0)          fail("busy still high with done");
            @(negedge clk);
            if (done !== 1'b0)          fail("done wider than one cycle");
            if (product !== expected)   fail("product not held after done");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        if (busy !== 1'b0 || done !== 1'b0 || product !== 0) begin
            errors = errors + 1;
            $display("FAIL reset values");
        end
        rst_n = 1'b1;
        @(negedge clk);

        for (x = 0; x < (1 << W); x = x + 1)
            for (y = 0; y < (1 << W); y = y + 1)
                run_mult(x, y);

        $display("--------------------------------------------------");
        $display("shift_add_mult exhaustive test: %0d products checked, %0d errors",
                 checks, errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED");
        $finish;
    end

    initial begin
        #100_000_000;
        $display("TIMEOUT: simulation watchdog expired");
        $display("TESTS FAILED");
        $finish;
    end
endmodule
