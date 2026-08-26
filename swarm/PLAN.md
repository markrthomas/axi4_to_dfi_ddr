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
