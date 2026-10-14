`timescale 1ns/1ps
// W-bit ripple-carry adder built structurally from full_adder cells.
module ripple_carry_adder #(
    parameter W = 8
) (
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    input  wire         cin,
    output wire [W-1:0] sum,
    output wire         cout
);
    wire [W:0] carry;
    assign carry[0] = cin;

    genvar i;
    generate
        for (i = 0; i < W; i = i + 1) begin : g_fa
            full_adder u_fa (
                .a   (a[i]),
                .b   (b[i]),
                .cin (carry[i]),
                .sum (sum[i]),
                .cout(carry[i+1])
            );
        end
    endgenerate

    assign cout = carry[W];
endmodule
