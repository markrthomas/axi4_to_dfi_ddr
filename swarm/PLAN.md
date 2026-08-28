# Swarm Operating Plan

## Task lifecycle

1. Create a GitHub Issue from the swarm task form. The issue is the canonical
   task record and defines scope, acceptance criteria, verification, and the
   reviewer.
2. Assign one owner and one branch: `swarm/<issue-number>-<slug>`. Split work
   only along file boundaries with an explicit dependency in the issue.
3. The owner posts a short issue comment before implementation, after validation,
   and when blocked. Do not mirror this state in committed files.
4. Open a pull request that links the issue, names the validation commands and
   their result, and identifies any unrun optional gate.
5. A human reviews and merges. Agents never commit or push to `main`.

The first canonical task is [Issue #1](https://github.com/markrthomas/axi4_to_dfi_ddr/issues/1):
true dual-clock FIFO formal data-integrity and ordering checks.

## Required gates

The required repository gate is the open-source flow. Run the narrowest relevant
commands while iterating, then run the applicable final gate:

```sh
make -C test ci
make coverage
make cocotb
```

For FIFO or CDC changes, also run:

```sh
make formal-fifo
make -C verification/formal all
```

VCS/UVM is an optional licensed regression. Report it as unavailable when the
licensed toolchain is absent; do not convert a skip into a pass.

## Scope controls

- Keep the bridge simulation-oriented; prioritize CDC and verification hardening.
- Keep one task focused. Stop for a human decision when a task changes the
  supported AXI subset, DFI/PHY contract, or product target.
- Do not add provider automation, credentials, Railway, or plan-trigger
  workflows without a separately approved issue.

## Open item — UVM-on-Verilator smoke (`uvm_dv/vlt`): runtime hang

**Added 2026-08-28.** A license-free Verilator 5.050 UVM flow was added under
`uvm_dv/vlt` (Makefile + shim) with CI in `.github/workflows/verilator-uvm.yml`
(builds Verilator from source, installs **z3** for `randomize()` constraint
solving + `ccache`, then lint + `smoke_test`). Verilator (first tool to actually
parse this never-licensed bench) caught two real bugs, fixed in this pass:
`` `uvm_field_time `` (not a UVM macro) → `` `uvm_field_int ``, and an illegal
bit-select on a parenthesised expression → `ID_W'(...)`. **Lint and the full
`--binary` build are green.**

**Status: PARTIAL — runtime hang (report, do not fake a pass).** `smoke_test`
builds and launches, then **hangs** (no `$finish`): it hit the CI 30-min job
timeout. The build completes and the sim starts (`+UVM_TESTNAME=smoke_test`),
so the deadlock is in the run — most likely the first AXI request never receives
its DFI/DDR response (analogous to the axi-on-ucie credit-return deadlock).

**Next step:** bound the run with `+UVM_TIMEOUT=<n>us,NO` (as was done to
diagnose axi-on-ucie) to capture the last UVM activity before the stall and
pinpoint which handshake blocks (AXI B/R vs. the DFI command/response path).
Then fix the response/scheduler stall and re-enable a hard
`UVM_ERROR==0 && UVM_FATAL==0` gate. Keep reporting it as unavailable/partial
until it genuinely drains — do not convert the hang into a pass.
