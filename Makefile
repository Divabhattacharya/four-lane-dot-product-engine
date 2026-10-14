# Four-Lane Dot-Product Engine
#   make test    run both self-checking testbenches (Icarus Verilog)
#   make synth   synthesize with Yosys and prove no multiplier is inferred
#   make wave    rebuild the engine testbench with VCD dumping
#   make clean

IVERILOG ?= iverilog
VVP      ?= vvp
YOSYS    ?= yosys

RTL   := rtl/full_adder.v rtl/ripple_carry_adder.v rtl/shift_add_mult.v rtl/dot_product_engine.v
BUILD := build

.PHONY: all test test_mult test_engine synth wave clean

all: test synth

test: test_mult test_engine

$(BUILD):
	mkdir -p $(BUILD)

test_mult: | $(BUILD)
	$(IVERILOG) -g2005 -Wall -o $(BUILD)/tb_shift_add_mult.vvp $(RTL) tb/tb_shift_add_mult.v
	$(VVP) -n $(BUILD)/tb_shift_add_mult.vvp | tee $(BUILD)/tb_shift_add_mult.log
	@grep -q "ALL TESTS PASSED" $(BUILD)/tb_shift_add_mult.log

test_engine: | $(BUILD)
	$(IVERILOG) -g2005 -Wall -o $(BUILD)/tb_dot_product_engine.vvp $(RTL) tb/tb_dot_product_engine.v
	$(VVP) -n $(BUILD)/tb_dot_product_engine.vvp | tee $(BUILD)/tb_dot_product_engine.log
	@grep -q "ALL TESTS PASSED" $(BUILD)/tb_dot_product_engine.log

# Elaborate first and assert there is no $mul cell (i.e. no '*' anywhere),
# then run a generic synthesis and print the cell statistics.
synth: | $(BUILD)
	$(YOSYS) -q -l $(BUILD)/synth.log -p "\
	    read_verilog $(RTL); \
	    hierarchy -check -top dot_product_engine; \
	    proc; flatten; opt; \
	    select -assert-none t:\$$mul; \
	    synth -top dot_product_engine; \
	    check -assert; \
	    tee -o $(BUILD)/synth_stat.txt stat"
	@echo "synthesis OK: no multiplier cells inferred"
	@cat $(BUILD)/synth_stat.txt

wave: | $(BUILD)
	$(IVERILOG) -g2005 -DDUMP -o $(BUILD)/tb_dot_product_engine_wave.vvp $(RTL) tb/tb_dot_product_engine.v
	cd $(BUILD) && $(VVP) -n tb_dot_product_engine_wave.vvp

clean:
	rm -rf $(BUILD)
