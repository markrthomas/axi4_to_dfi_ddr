# CLAUDE.md

Orientation auto-loaded into each Claude session in this repo.

## UVM on open-source Verilator (`uvm_dv/vlt`) — PARTIAL

License-free UVM-on-Verilator flow added 2026-08-28 (CI:
`.github/workflows/verilator-uvm.yml`; builds Verilator 5.050 from source +
installs **z3** for `randomize()` + `ccache`). Lint and the `--binary` build
**pass**, but the `smoke_test` smoke run currently **HANGS at runtime** (no `$finish`) —
a documented design blocker. Diagnosis + next step in `swarm/PLAN.md`.

Local lint (RAM-safe): `( unset VERILATOR_ROOT; make -C uvm_dv/vlt lint VERILATOR=~/verilator/bin/verilator UVM_HOME=~/verilator/test_regress/t/uvm )`
