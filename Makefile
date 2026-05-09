# Root Makefile: shortcuts and unified clean (run from repository root).
#
# Simulation details: test/Makefile
# Documentation details: doc/Makefile

.PHONY: help clean run test build vcd wave doc doc-html ci audit syn-check formal-fifo \
        lint regress coverage formal

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
	@echo "See README.md for full instructions and per-directory make -C usage."

clean:
	$(MAKE) -C test clean
	$(MAKE) -C doc clean

run test:
	$(MAKE) -C test run

ci:
	$(MAKE) -C test ci

syn-check:
	$(MAKE) -C test syn-check

formal-fifo:
	$(MAKE) -C test formal-fifo

# Standard DV gate targets (consistent with other RTL repos).
# lint: Verilator RTL lint (delegates to test/Makefile lint-verilator).
lint:
	$(MAKE) -C test lint-verilator

# regress: fast CI gate — lint + basic directed sim.
regress: lint
	$(MAKE) -C test run run-smoke run-smoke-zc run-smoke-refresh run-smoke-tras
	@echo "[REGRESS] lint + directed sim PASSED"

# coverage: Verilator C++ wrapper not yet written for this repo.
#           See doc/FULL_FUNCTIONALITY_PLAN.md Phase 6.
coverage:
	@echo "[COVERAGE] Verilator C++ wrapper not yet written for this repo."
	@echo "           Add a sim_main.cpp and wire --coverage to enable line coverage."
	@echo "           See doc/FULL_FUNCTIONALITY_PLAN.md Phase 6 and DV_STANDARDS.md."

# formal: Yosys formal targets (FIFO BMC + synthesis check).
formal: syn-check formal-fifo

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
