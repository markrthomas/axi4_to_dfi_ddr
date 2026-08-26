# Swarm Architecture

## Sources of truth

| Concern | Source |
|---|---|
| Task backlog, assignment, and current status | GitHub Issues |
| Durable technical architecture | `doc/DESIGN_SPEC.md` |
| Product and verification backlog | `doc/FULL_FUNCTIONALITY_PLAN.md` |
| Baseline evidence and limitations | `doc/INITIAL_ARCHITECTURE_BASELINE_REPORT.md` |
| Swarm decisions and operating rules | `swarm/DECISIONS.md`, `swarm/PLAN.md`, `swarm/AGENTS.md` |

## Repository work streams

- **RTL/CDC:** `src/cdc_fifo_lib.v`, `src/axi4_bridge_frontend.v`, and the
  top-level bridge integration.
- **DFI scheduler:** `src/mc_dfi_scheduler.v` and `src/dfi_adapter.v`.
- **Verification:** Icarus directed tests under `src/` and `test/`, cocotb under
  `cocotb/`, optional VCS/UVM under `uvm_dv/`, and formal under `formal/` and
  `verification/formal/`.
- **Quality gates:** GitHub Actions and the Makefile targets described in
  `swarm/PLAN.md`.

The current swarm scope is verification hardening. Do not treat this file as a
replacement for the design specification.
