# Four-Lane Dot-Product Engine

Verilog RTL for a 4-lane, 8-bit unsigned dot-product unit:

```
result = a0*b0 + a1*b1 + a2*b2 + a3*b3        (18-bit result)
```

There is no `*` operator anywhere in the RTL. Every multiply is a sequential
shift-and-add unit, and every add is a structural ripple-carry adder built from
full-adder cells.

## Architecture

```
            start                                   done, result (registered)
              |                                            ^
        +-----v------------------- control FSM ------------+------+
        |  IDLE ---> MULT ---> REDUCE ---> FINAL ---> IDLE        |
        +-----+-------------------+-----------+-------------------+
              | mult_start        | load       | load
   a0,b0 -> [shift_add_mult] p0 -+-> [+] -> s01_q -+
   a1,b1 -> [shift_add_mult] p1 -+                 +-> [+] -> result
   a2,b2 -> [shift_add_mult] p2 -+-> [+] -> s23_q -+
   a3,b3 -> [shift_add_mult] p3 -+
```

| File | Contents |
|---|---|
| `rtl/full_adder.v` | 1-bit full adder cell |
| `rtl/ripple_carry_adder.v` | parameterized W-bit adder generated from `full_adder` |
| `rtl/shift_add_mult.v` | sequential multiplier: multiplicand register, accumulator + multiplier shift register, iteration counter, one add-and-shift per cycle |
| `rtl/dot_product_engine.v` | 4 parallel multipliers, 2-level adder tree with a pipeline register between levels, control FSM, start/done handshake |
| `tb/tb_shift_add_mult.v` | exhaustive self-checking testbench for the multiplier |
| `tb/tb_dot_product_engine.v` | self-checking testbench for the engine against a behavioral reference model |

**Handshake.** `start` is sampled only in `IDLE` and is ignored while `busy`.
Operands are captured in the cycle `start` is accepted. `done` is a registered
one-cycle pulse, and `result` is registered and held until the next transaction
completes. Latency from start to done is W + 3 = 11 cycles. A new `start` can be
issued in the same cycle as `done`.

**Reset.** Asynchronous, active-low (`rst_n`). It clears the FSM, the pipeline
registers, `result`, `done`, and all multiplier state.

## Verification

Requirements: Icarus Verilog and Yosys (tested with Icarus Verilog 13.0 and Yosys 0.70).

```
make test     # both testbenches (Icarus Verilog)
make synth    # Yosys: assert no $mul cell, generic synthesis, cell stats
make wave     # VCD dump for GTKWave
```

`tb_shift_add_mult` checks all 65,536 operand pairs. While the multiplier is busy
it drives random operands and random `start` pulses, all of which must be ignored.
It also checks latency, the one-cycle `done` pulse, and that the product is held
afterwards.

`tb_dot_product_engine` compares every transaction against a behavioral
reference model (`ref_dot`), across these groups:

1. reset values
2. corner cases: all-zero, all-maximum (largest possible result), max × 0,
   single active lanes, mismatched lanes, carry into bit 16, alternating bit
   patterns, powers of two
3. 5,000 random transactions; every fourth one also gets operand and `start`
   noise while busy
4. repeated identical transactions
5. 200 back-to-back transactions, each new `start` issued in the same cycle as `done`
6. an asynchronous reset at every cycle of a transaction, followed by a check
   that no stale `done` or `busy` appears and that the next transaction is correct

Results:

```
shift_add_mult exhaustive test: 65536 products checked, 0 errors
dot_product_engine: 5247 transactions, 13 in-flight resets, 0 errors
latency start->done = 11 cycles
synthesis OK: no multiplier cells inferred   (167 flip-flops, generic gates)
```

**Testbench sensitivity.** Each of the following bugs was injected on its own,
and every one made the testbenches fail: a broken full-adder carry, a multiplier
off-by-one iteration count, a multiplier that accepts `start` while busy, a
dropped adder-tree carry, an engine that accepts `start` while busy, a `done`
that is not a pulse, and a `result` that is not cleared by reset. Adding a `*`
to the RTL makes `make synth` fail.
