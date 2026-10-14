`timescale 1ns/1ps
// Four-lane dot-product engine:
//
//     result = a0*b0 + a1*b1 + a2*b2 + a3*b3      (unsigned, W-bit operands)
//
//  * four shift_add_mult units, one per lane, run in parallel
//  * two-level adder tree built from ripple_carry_adder, with a pipeline
//    register between the levels
//  * control FSM:  IDLE -> MULT -> REDUCE -> FINAL -> IDLE
//
// Handshake: start is sampled only in IDLE (it is ignored while busy).
// Operands are captured on the cycle start is accepted. done is a registered
// one-cycle pulse; result is registered and held until the next transaction
// finishes. Latency from start to done is W + 3 cycles.
module dot_product_engine #(
    parameter W = 8
) (
    input  wire           clk,
    input  wire           rst_n,
    input  wire           start,
    input  wire [4*W-1:0] a_vec,      // {a3, a2, a1, a0}
    input  wire [4*W-1:0] b_vec,      // {b3, b2, b1, b0}
    output reg  [2*W+1:0] result,     // 4 * (2^W - 1)^2 needs 2W + 2 bits
    output wire           busy,
    output reg            done
);
    localparam PW = 2 * W;            // product width

    localparam [1:0] S_IDLE   = 2'd0,
                     S_MULT   = 2'd1,
                     S_REDUCE = 2'd2,
                     S_FINAL  = 2'd3;

    reg [1:0] state_q;

    // ------------------------------------------------------------------
    // Lane multipliers
    // ------------------------------------------------------------------
    wire            mult_start = (state_q == S_IDLE) && start;
    wire [4*PW-1:0] prod;             // {p3, p2, p1, p0}
    wire [3:0]      mult_busy;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : g_lane
            shift_add_mult #(.W(W)) u_mult (
                .clk         (clk),
                .rst_n       (rst_n),
                .start       (mult_start),
                .multiplicand(a_vec[i*W +: W]),
                .multiplier  (b_vec[i*W +: W]),
                .product     (prod[i*PW +: PW]),
                .busy        (mult_busy[i]),
                .done        ()
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // Adder tree
    // level 1: (p0 + p1), (p2 + p3)  -> PW + 1 bits each, registered
    // level 2: s01 + s23             -> PW + 2 bits, registered into result
    // ------------------------------------------------------------------
    wire [PW-1:0] s01, s23;
    wire          c01, c23;

    ripple_carry_adder #(.W(PW)) u_add01 (
        .a   (prod[0*PW +: PW]),
        .b   (prod[1*PW +: PW]),
        .cin (1'b0),
        .sum (s01),
        .cout(c01)
    );

    ripple_carry_adder #(.W(PW)) u_add23 (
        .a   (prod[2*PW +: PW]),
        .b   (prod[3*PW +: PW]),
        .cin (1'b0),
        .sum (s23),
        .cout(c23)
    );

    reg  [PW:0] s01_q, s23_q;         // pipeline register between tree levels
    wire [PW:0] s_total;
    wire        c_total;

    ripple_carry_adder #(.W(PW + 1)) u_add_final (
        .a   (s01_q),
        .b   (s23_q),
        .cin (1'b0),
        .sum (s_total),
        .cout(c_total)
    );

    // ------------------------------------------------------------------
    // Control FSM
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            s01_q   <= {(PW+1){1'b0}};
            s23_q   <= {(PW+1){1'b0}};
            result  <= {(PW+2){1'b0}};
            done    <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state_q)
                S_IDLE: begin
                    if (start)
                        state_q <= S_MULT;      // multipliers load this edge
                end
                S_MULT: begin
                    if (mult_busy == 4'b0000)
                        state_q <= S_REDUCE;
                end
                S_REDUCE: begin
                    s01_q   <= {c01, s01};
                    s23_q   <= {c23, s23};
                    state_q <= S_FINAL;
                end
                S_FINAL: begin
                    result  <= {c_total, s_total};
                    done    <= 1'b1;
                    state_q <= S_IDLE;
                end
                default: state_q <= S_IDLE;
            endcase
        end
    end

    assign busy = (state_q != S_IDLE);
endmodule
