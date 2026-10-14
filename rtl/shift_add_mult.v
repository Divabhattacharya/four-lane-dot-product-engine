`timescale 1ns/1ps
// Sequential unsigned shift-and-add multiplier.
//
// Datapath (right-shift form):
//   m_q   multiplicand, held for the whole operation
//   a_q   upper half of the product (accumulator)
//   q_q   lower half of the product; starts out holding the multiplier
//   cnt_q iteration counter, W iterations
//
// Each cycle:  if q_q[0] then {C, A} = A + M ;  {C, A, Q} >>= 1
// After W cycles the 2W-bit product is {a_q, q_q}.
//
// The add uses the structural ripple_carry_adder, so there is no '*' operator
// and synthesis cannot infer a hard multiplier / DSP block.
module shift_add_mult #(
    parameter W = 8
) (
    input  wire           clk,
    input  wire           rst_n,
    input  wire           start,          // accepted only while !busy
    input  wire [W-1:0]   multiplicand,
    input  wire [W-1:0]   multiplier,
    output wire [2*W-1:0] product,        // valid when done, held until next start
    output reg            busy,
    output reg            done            // one-cycle pulse
);
    localparam CW = (W > 1) ? $clog2(W) : 1;

    reg  [W-1:0]  m_q;
    reg  [W-1:0]  a_q;
    reg  [W-1:0]  q_q;
    reg  [CW-1:0] cnt_q;

    // add the multiplicand only when the current multiplier bit is 1
    wire [W-1:0]  addend = q_q[0] ? m_q : {W{1'b0}};
    wire [W-1:0]  sum;
    wire          carry;

    ripple_carry_adder #(.W(W)) u_add (
        .a   (a_q),
        .b   (addend),
        .cin (1'b0),
        .sum (sum),
        .cout(carry)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_q   <= {W{1'b0}};
            a_q   <= {W{1'b0}};
            q_q   <= {W{1'b0}};
            cnt_q <= {CW{1'b0}};
            busy  <= 1'b0;
            done  <= 1'b0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                if (start) begin
                    m_q   <= multiplicand;
                    a_q   <= {W{1'b0}};
                    q_q   <= multiplier;
                    cnt_q <= {CW{1'b0}};
                    busy  <= 1'b1;
                end
            end else begin
                // add and shift right in the same cycle
                {a_q, q_q} <= {carry, sum, q_q[W-1:1]};
                cnt_q      <= cnt_q + 1'b1;
                if (cnt_q == W-1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end

    assign product = {a_q, q_q};
endmodule
