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

.PHONY: help clean run test sim build vcd wave doc doc-html ci audit syn-check synth cdc dft lp gls ppa pkg formal-fifo formal-fifo-dual-clock \
        lint check regress coverage formal cocotb

help:
	@echo "axi4_to_dfi_ddr (repo root)"
	@echo "  make run       - compile (if needed) and run simulation"
	@echo "  make test      - same as run"
	@echo "  make ci        - sims + smokes + elab-fail + Verilator + yosys syn + yosys formal-fifo (if yosys)"
	@echo "  make audit     - make ci then build design PDF (pandoc + pdflatex)"
	@echo "  make build     - compile simulation only (test/build/sim.vvp)"
	@echo "  make vcd       - run simulation with +vcd (test/build/sim.vcd)"
	@echo "  make wave      - random-seed sim + VCD, then gtkwave w/ test/waves.gtkw (SEED=<n> to replay)"
	@echo "  make doc       - design PDF (doc/build/design_spec.pdf)"
	@echo "  make doc-html  - design HTML (doc/build/design_spec.html)"
	@echo "  make clean     - remove test/build/ and doc/build/"
	@echo "  make syn-check   - Yosys elaboration on syn/yosys.ys (skip if yosys missing)"
	@echo "  make formal-fifo - Yosys BMC on formal/fifo_safety_top.sv (skip if yosys missing)"
	@echo "  make formal-fifo-dual-clock - SymbiYosys dual-clock FIFO BMC (skip if sby missing)"
	@echo "  make lint      - Verilator RTL lint (skip if verilator missing)"
	@echo "  make check     - light local gate: lint + sim"
	@echo "  make regress   - fuller local gate: check + smokes"
	@echo "  make coverage  - Verilator line coverage (coverage.info)"
	@echo "  make stress    - stress / randomized simulation (n/a stub if none)"
	@echo "  make formal    - SymbiYosys formal (falls back to formal-fifo if sby missing)"
	@echo "See DV_STANDARDS.md for the common make-target vocabulary shared across sibling repos."
	@echo "See README.md for full instructions and per-directory make -C usage."
	@echo "  swarm      Swarm A (verification) via Claude Code; swarm-rr = Swarm B (random regression); swarm-dry = show the command"
	@echo "  batch      the Railway batch (docker/entrypoint.sh ci); board = swarm status; heavy T=<t> = one heavy target at a time"
	@echo "  swarm-profile / swarm-kit-check   print .claude/swarm.env / check kit drift (shared kit: markrthomas/dv-swarm-kit)"

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

# check: light local gate — lint + the functional/directed sim tier.
# Fast enough to run on every save; see DV_STANDARDS.md.
check: lint sim

# regress: fast CI gate — lint + basic directed sim.
regress: lint
	$(MAKE) -C test run run-smoke run-smoke-zc run-smoke-refresh run-smoke-tras
	@echo "[REGRESS] lint + directed sim PASSED"

# synth: T1 synthesizability + area/timing-proxy gate (Yosys, OSS — no PDK).
#   1. no inferred latches ($_DLATCH_); 2. cell count <= SYNTH_MAX_CELLS (area
#   ceiling); 3. longest topological logic depth (ltp) <= SYNTH_MAX_DEPTH (a
#   liberty-free critical-path proxy). Emits a flat gate netlist (sim/synth_netlist.v).
#   Ceilings set above the current design (13090 cells / depth 46) to absorb
#   yosys drift while catching real ballooning. Part of the tapeout-readiness
#   program — see syn/SIGNOFF.md. Requires yosys on PATH.
SYNTH_MAX_CELLS ?= 18000
SYNTH_MAX_DEPTH ?= 70
synth:
	@set -e; \
	command -v yosys >/dev/null 2>&1 || { echo "[SYNTH] yosys not on PATH; skipping"; exit 0; }; \
	echo "[SYNTH] synthesizing (generic gate map, flattened)..."; mkdir -p sim; \
	yosys -p "read_verilog -Isrc $(BRIDGE_SRCS); \
		synth -top axi4_to_dfi_bridge -flatten; \
		stat; ltp -noff; write_verilog sim/synth_netlist.v" > sim/synth.log 2>&1; \
	if grep -qE '\$$_DLATCH' sim/synth.log; then echo "[SYNTH] FAIL: inferred latch cells!"; exit 1; fi; \
	cells=$$(grep -oE '[0-9]+ cells$$' sim/synth.log | tail -1 | grep -oE '[0-9]+'); \
	depth=$$(grep -oE 'length=[0-9]+' sim/synth.log | tail -1 | grep -oE '[0-9]+'); \
	echo "[SYNTH] cells=$${cells:-?} logic-depth(ltp)=$${depth:-?} ceilings: cells<=$(SYNTH_MAX_CELLS) depth<=$(SYNTH_MAX_DEPTH)"; \
	echo "[SYNTH] netlist: sim/synth_netlist.v (full log: sim/synth.log)"; \
	fail=0; \
	if [ -n "$$cells" ] && [ "$$cells" -gt "$(SYNTH_MAX_CELLS)" ]; then echo "[SYNTH] FAIL: cells $$cells > $(SYNTH_MAX_CELLS)"; fail=1; fi; \
	if [ -n "$$depth" ] && [ "$$depth" -gt "$(SYNTH_MAX_DEPTH)" ]; then echo "[SYNTH] FAIL: depth $$depth > $(SYNTH_MAX_DEPTH)"; fail=1; fi; \
	[ "$$fail" -eq 0 ] || exit 1; \
	echo "[SYNTH] PASS: no latches; area & timing-proxy within ceilings"

# cdc: structural clock-domain-crossing audit (Yosys). Blackboxes the sanctioned
#   synchronizers (async_fifo_gray, cdc_sync) then asserts no axi_aclk<->dfi_clk flop
#   crossing bypasses one. Fails (non-zero) on any unsynchronized crossing. This is
#   the real multi-clock CDC gate this block needs (vs single-clock siblings).
cdc:
	@set -e; \
	command -v yosys >/dev/null 2>&1 || { echo "[CDC] yosys not on PATH; skipping"; exit 0; }; \
	echo "[CDC] auditing AXI<->DFI clock-domain crossings..."; mkdir -p sim; \
	yosys verification/cdc/cdc_audit.ys > sim/cdc.log 2>&1 || { \
		echo "[CDC] FAIL: unsynchronized clock-domain crossing (see sim/cdc.log)"; \
		grep -i 'Assertion failed' sim/cdc.log || true; exit 1; }; \
	echo "[CDC] PASS: every AXI<->DFI crossing goes through a sanctioned synchronizer"

# dft: T4 DFT scan-readiness audit (Yosys, OSS — no PDK). On the synthesized netlist,
#      asserts latch-free + no combinational loops (HARD gates) and inventories flops /
#      reset controllability / async set-reset / RAM for scan planning. Scan insertion +
#      ATPG = needs-license (see syn/dft/DFT_PLAN.md). Part of the tapeout-readiness program.
dft:
	@command -v yosys >/dev/null 2>&1 || { echo "[DFT] yosys not on PATH; skipping"; exit 0; }
	@bash $(CURDIR)/syn/dft/scan_readiness.sh

# lp: T3 low-power UPF consistency lint (tclsh, OSS — no PDK). Cross-checks the IEEE-1801
#     UPF (domains / supplies / isolation / retention / power-state table) for internal
#     consistency. Power-aware sim + RTL<->UPF LEC = needs-license (see syn/lp/LP_PLAN.md).
lp:
	@command -v tclsh >/dev/null 2>&1 || { echo "[LP] tclsh not on PATH; skipping"; exit 0; }
	@tclsh $(CURDIR)/syn/lp/upf_lint.tcl $(CURDIR)/syn/lp/axi_dfi.upf

# gls: T6 zero-delay gate-level sim (Yosys + Icarus, OSS — no PDK). Synthesizes the top to
#      a generic-gate netlist (at the TB's param overrides) and runs the directed
#      self-checking TB against it. SDF-timing GLS + Liberty map = needs-pdk (syn/gls/T6_PLAN.md).
gls:
	@bash $(CURDIR)/syn/gls/gls.sh

# ppa: T6 PPA proxy baseline (Yosys, OSS — no PDK). Tracks generic cells + flops (area) and
#      logic depth / ltp (timing) per top. Real area/power/timing = needs-pdk (syn/ppa/PPA_PLAN.md).
ppa:
	@bash $(CURDIR)/syn/ppa/ppa.sh

# pkg: T7 packaging gate (OSS). Validates the IP-XACT (IEEE 1685-2014) component:
#      well-formed + structural + a hard IP-XACT<->RTL model-port match (fails on drift).
pkg:
	@command -v xmllint >/dev/null 2>&1 || { echo "[PKG] xmllint not on PATH; skipping"; exit 0; }
	@bash $(CURDIR)/pkg/check_ipxact.sh

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

# Standard DV target (DV_STANDARDS.md)
.PHONY: stress
stress:
	@echo "[STRESS] n/a: no stress/randomized tier in this repo yet (see DV_STANDARDS.md)"

# shared swarm/infra targets (markrthomas/dv-swarm-kit)
# --- T7 full XSD validation + release bundle; T2/T6 sky130 silicon run (kit templates/signoff/) ---
include pkg/pkg-xsd.mk
RELEASE_OUT ?= dist
REL_NAME := axi4-to-dfi-ddr
PNR_TOPS ?= axi4_to_dfi_bridge
.PHONY: release release-verify release-check pnr gls-sky130

release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z"; exit 2; }
	python3 $(CURDIR)/scripts/make_release.py --version $(VERSION) --out $(RELEASE_OUT) $(if $(ALLOW_DIRTY),--allow-dirty)

release-verify:
	@test -n "$(VERSION)" || { echo "usage: make release-verify VERSION=x.y.z"; exit 2; }
	python3 $(CURDIR)/scripts/make_release.py --verify $(RELEASE_OUT)/$(REL_NAME)-$(VERSION).tar.gz

# Dry run (CI): two builds must be byte-identical and verify. Not a release (T0 open).
release-check:
	python3 $(CURDIR)/scripts/make_release.py --version 0.0.0-ci --out /tmp/rel-a $(if $(ALLOW_DIRTY),--allow-dirty)
	python3 $(CURDIR)/scripts/make_release.py --version 0.0.0-ci --out /tmp/rel-b $(if $(ALLOW_DIRTY),--allow-dirty)
	cmp /tmp/rel-a/$(REL_NAME)-0.0.0-ci.tar.gz /tmp/rel-b/$(REL_NAME)-0.0.0-ci.tar.gz && echo "[REL] reproducible: two builds are byte-identical"
	python3 $(CURDIR)/scripts/make_release.py --verify /tmp/rel-a/$(REL_NAME)-0.0.0-ci.tar.gz

# Heavy (LibreLane in Docker, ~GBs): run in CI (.github/workflows/silicon.yml), not locally.
pnr:
	@for t in $(or $(TOP),$(PNR_TOPS)); do bash $(CURDIR)/syn/pnr/run_pnr.sh $$t || exit 1; done

gls-sky130:
	@for t in $(or $(TOP),$(PNR_TOPS)); do bash $(CURDIR)/syn/pnr/gls_sky130.sh $$t || exit 1; done

include swarm.mk
