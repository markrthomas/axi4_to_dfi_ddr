# Root Makefile: shortcuts and unified clean (run from repository root).
#
# Simulation details: test/Makefile
# Documentation details: doc/Makefile

VERILATOR ?= verilator
VERILATOR_ROOT := $(shell v=$$(command -v verilator 2>/dev/null); [ -n "$$v" ] && realpath "$$(dirname "$$v")/../share/verilator")
VERILATOR_INC  := $(VERILATOR_ROOT)/include
VERILATOR_CPP  := $(VERILATOR_INC)/verilated.cpp $(VERILATOR_INC)/verilated_cov.cpp \
                  $(VERILATOR_INC)/verilated_threads.cpp

BRIDGE_SRCS := src/cdc_fifo_lib.v src/mc_dfi_scheduler.v src/axi4_bridge_frontend.v \
               src/dfi_adapter.v src/axi4_to_dfi_bridge.v
COV_DIR := obj_dir_cov

.PHONY: help clean run test sim build vcd wave doc doc-html ci audit syn-check formal-fifo formal-fifo-dual-clock \
        lint regress coverage formal cocotb

help:
	@echo "axi4_to_dfi_ddr (repo root)"
	@echo "  make run       - compile (if needed) and run simulation"
	@echo "  make test      - same as run"
	@echo "  make ci        - sims + smokes + elab-fail + Verilator + yosys syn + yosys formal-fifo (if yosys)"
	@echo "  make audit     - make ci then build design PDF (pandoc + pdflatex)"
	@echo "  make build     - compile simulation only (test/build/sim.vvp)"
	@echo "  make vcd       - run simulation with +vcd (test/build/sim.vcd)"
	@echo "  make wave      - vcd + gtkwave"
	@echo "  make doc       - design PDF (doc/build/design_spec.pdf)"
	@echo "  make doc-html  - design HTML (doc/build/design_spec.html)"
	@echo "  make clean     - remove test/build/ and doc/build/"
	@echo "  make syn-check   - Yosys elaboration on syn/yosys.ys (skip if yosys missing)"
	@echo "  make formal-fifo - Yosys BMC on formal/fifo_safety_top.sv (skip if yosys missing)"
	@echo "  make formal-fifo-dual-clock - SymbiYosys dual-clock FIFO BMC (skip if sby missing)"
	@echo "See README.md for full instructions and per-directory make -C usage."

clean:
	$(MAKE) -C test clean
	$(MAKE) -C doc clean
	rm -rf $(COV_DIR) coverage.info

run test sim:
	$(MAKE) -C test run

ci:
	$(MAKE) -C test ci

syn-check:
	$(MAKE) -C test syn-check

formal-fifo:
	$(MAKE) -C test formal-fifo

formal-fifo-dual-clock:
	$(MAKE) -C verification/formal dual-clock

# Standard DV gate targets (consistent with other RTL repos).
# lint: Verilator RTL lint (delegates to test/Makefile lint-verilator).
lint:
	$(MAKE) -C test lint-verilator

# regress: fast CI gate — lint + basic directed sim.
regress: lint
	$(MAKE) -C test run run-smoke run-smoke-zc run-smoke-refresh run-smoke-tras
	@echo "[REGRESS] lint + directed sim PASSED"

# coverage: Verilator --coverage build + run; emits coverage.info (lcov format).
coverage:
	@command -v $(VERILATOR) >/dev/null 2>&1 || { echo "[COVERAGE] verilator not on PATH; skipping"; exit 0; }
	rm -rf $(COV_DIR)
	$(VERILATOR) --coverage -cc $(BRIDGE_SRCS) --top-module axi4_to_dfi_bridge \
		--Mdir $(COV_DIR) -Wno-DECLFILENAME -Wno-WIDTH -Wno-UNUSED -Wno-fatal
	$(MAKE) -C $(COV_DIR) -f Vaxi4_to_dfi_bridge.mk
	g++ -DVM_COVERAGE=1 -o $(COV_DIR)/sim_cov \
		sim_main.cpp $(COV_DIR)/Vaxi4_to_dfi_bridge__ALL.a \
		-I$(COV_DIR) -I$(VERILATOR_INC) -I$(VERILATOR_INC)/vltstd \
		$(VERILATOR_CPP) -pthread -lm
	cd $(COV_DIR) && ./sim_cov
	@if command -v verilator_coverage >/dev/null 2>&1; then \
		cd $(COV_DIR) && verilator_coverage --write-info ../coverage.info coverage.dat && \
		test -s ../coverage.info && \
		echo "[COVERAGE] coverage.info written"; \
	else \
		echo "[COVERAGE] coverage.dat in $(COV_DIR) (install verilator for lcov export)"; \
	fi

# formal: SymbiYosys formal (verification/formal/); falls back to legacy Yosys
#         formal-fifo if sby is not installed.
formal:
	@if command -v sby >/dev/null 2>&1; then \
		$(MAKE) -C $(CURDIR)/verification/formal; \
	else \
		echo "[FORMAL] sby not found; running legacy Yosys formal-fifo"; \
		$(MAKE) formal-fifo; \
	fi

cocotb:
	$(MAKE) -C $(CURDIR)/cocotb

audit: ci
	$(MAKE) -C doc pdf

build:
	$(MAKE) -C test build

vcd wave:
	$(MAKE) -C test $@

doc:
	$(MAKE) -C doc pdf

doc-html:
	$(MAKE) -C doc html
