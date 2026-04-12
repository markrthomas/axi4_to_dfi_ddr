# Root Makefile: shortcuts and unified clean (run from repository root).
#
# Simulation details: test/Makefile
# Documentation details: doc/Makefile

.PHONY: help clean run test build vcd wave doc doc-html ci

help:
	@echo "axi4_to_dfi_ddr (repo root)"
	@echo "  make run       - compile (if needed) and run simulation"
	@echo "  make test      - same as run"
	@echo "  make ci        - sims + param smokes + elab-fail guards + Verilator lint (see test/Makefile)"
	@echo "  make build     - compile simulation only (test/build/sim.vvp)"
	@echo "  make vcd       - run simulation with +vcd (test/build/sim.vcd)"
	@echo "  make wave      - vcd + gtkwave"
	@echo "  make doc       - design PDF (doc/build/design_spec.pdf)"
	@echo "  make doc-html  - design HTML (doc/build/design_spec.html)"
	@echo "  make clean     - remove test/build/ and doc/build/"
	@echo "See README.md for full instructions and per-directory make -C usage."

clean:
	$(MAKE) -C test clean
	$(MAKE) -C doc clean

run test:
	$(MAKE) -C test run

ci:
	$(MAKE) -C test ci

build:
	$(MAKE) -C test build

vcd wave:
	$(MAKE) -C test $@

doc:
	$(MAKE) -C doc pdf

doc-html:
	$(MAKE) -C doc html
