# Build and run AXI4→DFI bridge simulation (Icarus Verilog).
#
# Usage (from repo root):  make -C test <target>
# Usage (from test/):      make <target>
#
# Targets:
#   build   Compile only (outputs build/sim.vvp)
#   run     Build if needed, run simulation (default for `all`)
#   test    Same as run
#   run-smoke  Compile tb_param_smoke (CDC_FIFO_DEPTH=16) and run
#   run-smoke-zc  tb_param_smoke_zcycles (zero MC/PHY timing waits + row change)
#   run-smoke-refresh  tb_param_smoke_refresh (MC_REFRESH_INTERVAL>0, PRE on walk)
#   run-smoke-tras  tb_param_smoke_tras (MC_T_RAS / MC_T_WR > 0, row-miss write)
#   elab-fail-*  Expect ERROR: from parameter guards (see tb_elab_fail.v)
#   lint-verilator  Verilator --lint-only on bridge RTL (optional tool)
#   syn-check  Yosys hierarchy/opt on ../syn/yosys.ys (skip if yosys not in PATH)
#   formal-fifo  Yosys BMC on formal/fifo_safety_top.sv (skip if yosys not in PATH)
#   ci      ... + syn-check + formal-fifo
#   vcd     Run with +vcd; writes build/sim.vcd for gtkwave
#   wave    Run vcd then launch gtkwave on build/sim.vcd (if gtkwave in PATH)
#   clean   Remove build/
#   help    Show this summary
#   doc     Build doc/build/design_spec.pdf (pandoc + pdflatex)
#   doc-html  Build doc/build/design_spec.html (pandoc only)

SRC_DIR   := ../src
DOC_DIR   := ../doc
BUILD_DIR := build
SIM       := $(BUILD_DIR)/sim.vvp
VCD       := $(BUILD_DIR)/sim.vcd
SOURCES   := $(SRC_DIR)/axi4_to_dfi_bridge.v $(SRC_DIR)/tb_axi4_to_dfi_bridge.v
SMOKE_TOP := tb_param_smoke
SMOKE_SIM := $(BUILD_DIR)/smoke.vvp
SMOKE_SRC := $(SRC_DIR)/axi4_to_dfi_bridge.v $(SRC_DIR)/tb_param_smoke.v
SMOKE_ZC_TOP := tb_param_smoke_zcycles
SMOKE_ZC_SIM := $(BUILD_DIR)/smoke_zc.vvp
SMOKE_ZC_SRC := $(SRC_DIR)/axi4_to_dfi_bridge.v $(SRC_DIR)/tb_param_smoke_zcycles.v
SMOKE_RF_TOP := tb_param_smoke_refresh
SMOKE_RF_SIM := $(BUILD_DIR)/smoke_refresh.vvp
SMOKE_RF_SRC := $(SRC_DIR)/axi4_to_dfi_bridge.v $(SRC_DIR)/tb_param_smoke_refresh.v
SMOKE_TRAS_TOP := tb_param_smoke_tras
SMOKE_TRAS_SIM := $(BUILD_DIR)/smoke_tras.vvp
SMOKE_TRAS_SRC := $(SRC_DIR)/axi4_to_dfi_bridge.v $(SRC_DIR)/tb_param_smoke_tras.v
ELAB_FAIL_SRC := $(SRC_DIR)/axi4_to_dfi_bridge.v $(SRC_DIR)/tb_elab_fail.v

IVERILOG  := iverilog
VVP       := vvp
IVERFLAGS := -g2001 -Wall
VERILATOR := verilator
# Lint-only: waive width/unused on this Verilog-2001 bridge (AXI tie-offs, FIFO PTRW ternary).
VERILINT  := $(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME -Wno-WIDTH -Wno-UNUSED

.PHONY: all build run test run-smoke run-smoke-zc run-smoke-refresh run-smoke-tras \
	elab-fail-width elab-fail-depth elab-fail-addrmap elab-fail-fifo \
	elab-fail-mcwide elab-fail-dfiinit-neg elab-fail-dfiinit-ovf elab-fail-all \
	lint-verilator syn-check formal-fifo ci vcd wave clean help doc doc-html

all: run

help:
	@echo "Targets: build run test run-smoke run-smoke-zc run-smoke-refresh run-smoke-tras elab-fail-* elab-fail-all lint-verilator syn-check formal-fifo ci vcd wave doc doc-html clean help"
	@echo "  build  - compile to $(SIM)"
	@echo "  run    - compile (if needed) and run tests"
	@echo "  run-smoke - compile $(SMOKE_SIM) and run tb_param_smoke"
	@echo "  run-smoke-zc - zero-cycle MC timing + row-miss smoke ($(SMOKE_ZC_SIM))"
	@echo "  run-smoke-refresh - MC_REFRESH_INTERVAL + refresh PRE ($(SMOKE_RF_SIM))"
	@echo "  run-smoke-tras - MC_T_RAS / MC_T_WR row-miss ($(SMOKE_TRAS_SIM))"
	@echo "  elab-fail-all - seven illegal configs must print ERROR: and finish"
	@echo "  lint-verilator - Verilator lint on $(SRC_DIR)/axi4_to_dfi_bridge.v (skip if no verilator)"
	@echo "  syn-check - Yosys on ../syn/yosys.ys (skip if no yosys)"
	@echo "  formal-fifo - Yosys BMC on async_fifo_gray wrapper (skip if no yosys)"
	@echo "  ci     - run + smokes (incl. tras) + elab-fail-all + lint + syn-check + formal-fifo"
	@echo "  vcd    - run tests and write $(VCD) (open with gtkwave)"
	@echo "  wave   - vcd + gtkwave $(VCD)"
	@echo "  doc    - PDF from $(DOC_DIR)/DESIGN_SPEC.md (requires pandoc + pdflatex)"
	@echo "  doc-html - HTML from design spec (pandoc only)"
	@echo "  clean  - remove $(BUILD_DIR)/ only (use repo root 'make clean' for doc too)"

build: $(SIM)

$(SIM): $(SOURCES)
	mkdir -p $(dir $@)
	$(IVERILOG) $(IVERFLAGS) -o $(SIM) $(SOURCES)

run: $(SIM)
	$(VVP) $(SIM)

test: run

$(SMOKE_SIM): $(SMOKE_SRC)
	mkdir -p $(dir $@)
	$(IVERILOG) $(IVERFLAGS) -o $@ -s $(SMOKE_TOP) $(SMOKE_SRC)

run-smoke: $(SMOKE_SIM)
	$(VVP) $(SMOKE_SIM)

$(SMOKE_ZC_SIM): $(SMOKE_ZC_SRC)
	mkdir -p $(dir $@)
	$(IVERILOG) $(IVERFLAGS) -o $@ -s $(SMOKE_ZC_TOP) $(SMOKE_ZC_SRC)

run-smoke-zc: $(SMOKE_ZC_SIM)
	$(VVP) $(SMOKE_ZC_SIM)

$(SMOKE_RF_SIM): $(SMOKE_RF_SRC)
	mkdir -p $(dir $@)
	$(IVERILOG) $(IVERFLAGS) -o $@ -s $(SMOKE_RF_TOP) $(SMOKE_RF_SRC)

run-smoke-refresh: $(SMOKE_RF_SIM)
	$(VVP) $(SMOKE_RF_SIM)

$(SMOKE_TRAS_SIM): $(SMOKE_TRAS_SRC)
	mkdir -p $(dir $@)
	$(IVERILOG) $(IVERFLAGS) -o $@ -s $(SMOKE_TRAS_TOP) $(SMOKE_TRAS_SRC)

run-smoke-tras: $(SMOKE_TRAS_SIM)
	$(VVP) $(SMOKE_TRAS_SIM)

elab-fail-width: $(ELAB_FAIL_SRC)
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVERFLAGS) -o $(BUILD_DIR)/elab_width.vvp -s tb_elab_fail_width $(ELAB_FAIL_SRC)
	$(VVP) $(BUILD_DIR)/elab_width.vvp 2>&1 | tee $(BUILD_DIR)/elab_width.log | grep -q "ERROR: axi4_to_dfi_bridge: C_AXI_DATA_WIDTH"

elab-fail-depth: $(ELAB_FAIL_SRC)
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVERFLAGS) -o $(BUILD_DIR)/elab_depth.vvp -s tb_elab_fail_depth $(ELAB_FAIL_SRC)
	$(VVP) $(BUILD_DIR)/elab_depth.vvp 2>&1 | tee $(BUILD_DIR)/elab_depth.log | grep -q "ERROR: axi4_to_dfi_bridge: CDC_FIFO_DEPTH"

elab-fail-addrmap: $(ELAB_FAIL_SRC)
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVERFLAGS) -o $(BUILD_DIR)/elab_addr.vvp -s tb_elab_fail_addrmap $(ELAB_FAIL_SRC)
	$(VVP) $(BUILD_DIR)/elab_addr.vvp 2>&1 | tee $(BUILD_DIR)/elab_addr.log | grep -q "ERROR: axi4_to_dfi_bridge: MC_COL_BITS"

elab-fail-fifo: $(ELAB_FAIL_SRC)
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVERFLAGS) -o $(BUILD_DIR)/elab_fifo.vvp -s tb_elab_fail_fifo $(ELAB_FAIL_SRC)
	$(VVP) $(BUILD_DIR)/elab_fifo.vvp 2>&1 | tee $(BUILD_DIR)/elab_fifo.log | grep -q "ERROR: async_fifo_gray"

elab-fail-mcwide: $(ELAB_FAIL_SRC)
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVERFLAGS) -o $(BUILD_DIR)/elab_mcwide.vvp -s tb_elab_fail_mcwide $(ELAB_FAIL_SRC)
	$(VVP) $(BUILD_DIR)/elab_mcwide.vvp 2>&1 | tee $(BUILD_DIR)/elab_mcwide.log | grep -q "8-bit counters"

elab-fail-dfiinit-neg: $(ELAB_FAIL_SRC)
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVERFLAGS) -o $(BUILD_DIR)/elab_dfiinit_neg.vvp -s tb_elab_fail_dfiinit_neg $(ELAB_FAIL_SRC)
	$(VVP) $(BUILD_DIR)/elab_dfiinit_neg.vvp 2>&1 | tee $(BUILD_DIR)/elab_dfiinit_neg.log | grep -q "DFI_INIT_START_CYCLES"

elab-fail-dfiinit-ovf: $(ELAB_FAIL_SRC)
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVERFLAGS) -o $(BUILD_DIR)/elab_dfiinit_ovf.vvp -s tb_elab_fail_dfiinit_ovf $(ELAB_FAIL_SRC)
	$(VVP) $(BUILD_DIR)/elab_dfiinit_ovf.vvp 2>&1 | tee $(BUILD_DIR)/elab_dfiinit_ovf.log | grep -q "DFI_INIT_START_CYCLES"

elab-fail-all: elab-fail-width elab-fail-depth elab-fail-addrmap elab-fail-fifo \
	elab-fail-mcwide elab-fail-dfiinit-neg elab-fail-dfiinit-ovf
	@echo "PASS: elab-fail-all (seven expected elaboration errors)"

# Note: each Makefile recipe line runs in a separate shell; put skip+run in one
# block so a missing tool does not fall through to the next line.
lint-verilator:
	@if command -v $(VERILATOR) >/dev/null 2>&1; then \
		$(VERILINT) $(SRC_DIR)/axi4_to_dfi_bridge.v; \
	else \
		echo "SKIP: verilator not in PATH"; \
	fi

syn-check:
	@if command -v yosys >/dev/null 2>&1; then \
		cd ../syn && yosys -q yosys.ys && \
		echo "PASS: syn-check (yosys on axi4_to_dfi_bridge)"; \
	else \
		echo "SKIP: yosys not in PATH"; \
	fi

formal-fifo:
	@if command -v yosys >/dev/null 2>&1; then \
		cd ../formal && yosys -q -s yosys_fifo_safety.ys && \
		echo "PASS: formal-fifo (yosys BMC on fifo_safety_top)"; \
	else \
		echo "SKIP: yosys not in PATH"; \
	fi

ci: run run-smoke run-smoke-zc run-smoke-refresh run-smoke-tras elab-fail-all lint-verilator syn-check formal-fifo

vcd: $(SIM)
	$(VVP) $(SIM) +vcd
	@echo "VCD: $(VCD)  (gtkwave $(VCD))"

wave: vcd
	@if command -v gtkwave >/dev/null 2>&1; then \
		gtkwave $(VCD) & \
	else \
		echo "gtkwave not found in PATH; open $(VCD) manually"; \
		exit 1; \
	fi

doc:
	$(MAKE) -C $(DOC_DIR) pdf

doc-html:
	$(MAKE) -C $(DOC_DIR) html

clean:
	rm -rf $(BUILD_DIR)
