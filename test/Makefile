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
#   elab-fail-*  Expect ERROR: from parameter guards (see tb_elab_fail.v)
#   lint-verilator  Verilator --lint-only on bridge RTL (optional tool)
#   ci      run + smoke + smoke-zc + elab-fail-all + lint-verilator
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
ELAB_FAIL_SRC := $(SRC_DIR)/axi4_to_dfi_bridge.v $(SRC_DIR)/tb_elab_fail.v

IVERILOG  := iverilog
VVP       := vvp
IVERFLAGS := -g2001 -Wall
VERILATOR := verilator
# Lint-only: waive width/unused on this Verilog-2001 bridge (AXI tie-offs, FIFO PTRW ternary).
VERILINT  := $(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME -Wno-WIDTH -Wno-UNUSED

.PHONY: all build run test run-smoke run-smoke-zc \
	elab-fail-width elab-fail-depth elab-fail-addrmap elab-fail-fifo elab-fail-all \
	lint-verilator ci vcd wave clean help doc doc-html

all: run

help:
	@echo "Targets: build run test run-smoke run-smoke-zc elab-fail-* elab-fail-all lint-verilator ci vcd wave doc doc-html clean help"
	@echo "  build  - compile to $(SIM)"
	@echo "  run    - compile (if needed) and run tests"
	@echo "  run-smoke - compile $(SMOKE_SIM) and run tb_param_smoke"
	@echo "  run-smoke-zc - zero-cycle MC timing + row-miss smoke ($(SMOKE_ZC_SIM))"
	@echo "  elab-fail-all - four illegal configs must print ERROR: and finish"
	@echo "  lint-verilator - Verilator lint on $(SRC_DIR)/axi4_to_dfi_bridge.v (skip if no verilator)"
	@echo "  ci     - run + run-smoke + run-smoke-zc + elab-fail-all + lint-verilator"
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

elab-fail-all: elab-fail-width elab-fail-depth elab-fail-addrmap elab-fail-fifo
	@echo "PASS: elab-fail-all (four expected elaboration errors)"

lint-verilator:
	@if ! command -v $(VERILATOR) >/dev/null 2>&1; then echo "SKIP: verilator not in PATH"; exit 0; fi
	$(VERILINT) $(SRC_DIR)/axi4_to_dfi_bridge.v

ci: run run-smoke run-smoke-zc elab-fail-all lint-verilator

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
