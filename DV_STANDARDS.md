# DV Standards — a common `make` target API across RTL/DV repos

This document formalizes a `make`-target convention shared across this
maintainer's RTL/DV repositories (the AXI/CHI/UCIe/CXL/PCIe bridge IPs and
their DV suites). It descends from the original `apb_mem` PyUVM/cocotb
reference (`uvm_review`), whose Makefile first stated: *"the standard DV gate
targets (help / lint / test / check / regress / ci / clean) shared with the
other RTL repos"*. That convention grew informally, repo by repo, and several
Makefiles already referenced an (uncommitted) `DV_STANDARDS.md` — this file is
that document, written down for the first time.

**Scope:** every repo in this family that does RTL + DV work at the `make
<target>` level, regardless of its actual simulator/toolchain (Icarus,
Verilator, a commercial UVM simulator, or a non-Make-native build system like
Bazel or pytest wrapped in a thin `make` shim).

**Principle: additive, never redefining.** This is descriptive of what already
exists, formalized — not a rewrite. A repo that already has a target from the
table below keeps its exact current name and behavior; nothing here asks any
existing target to change what it does. Where a repo lacks a name from the
table but has the underlying capability under a different name, add the
standard name as a thin alias/dependency line. Where a repo lacks the
underlying capability entirely, either omit the target or add one that prints
a one-line skip and exits 0 — never fail a build for a tier the repo doesn't
have, and never invent new verification work to satisfy a name.

## Core target vocabulary

| target | meaning | required? |
|---|---|---|
| `help` (also the default, no-arg `make`) | print the grouped target list; `make` alone must never silently run a gate | required |
| `lint` | fast static RTL lint (Verilator `--lint-only` or equivalent); no simulator run, degrades gracefully if the linter is absent | required |
| `test` | the cocotb/PyUVM functional DV tier, if the repo has one (some repos also expose this under its own name, e.g. `pyuvm` — `test` is the cross-repo alias) | if applicable |
| `cocotb` | alias for `test` / `pyuvm` — the name used by repos whose native functional-tier target is called something else | if applicable |
| `sim` | the primary directed/hand-written simulation entry point (Icarus or Verilator directed TB), where distinct from the cocotb tier | if applicable |
| `check` | the **light** local gate: `lint` + the functional tier (`test`/`sim`). Meant to be fast enough to run on every save. | required |
| `regress` | the **fuller** local gate: `check` plus whatever additional DV environments/tiers the repo has that are still fast enough to run locally (formal, additional directed envs, low-power/UPF emulation, etc. — repo-specific) | required |
| `coverage` | Verilator line coverage, gated on a `COV_MIN` variable; degrades to a skip + exit 0 if `verilator`/`verilator_coverage` is absent | required |
| `formal` | SymbiYosys BMC/cover proofs; degrades to a skip + exit 0 if `sby` is absent | if applicable |
| `fcov` | independent functional coverage (`cocotb_coverage` or equivalent), if authored | if applicable |
| `sva` | bound concurrent SVA checked under a Verilator `--assert` run, if authored | if applicable |
| `synth` | Yosys synthesis smoke (inferred-latch / area check), if authored | if applicable |
| `cdc` | structural clock-domain-crossing audit, if authored | if applicable |
| `uvm` | the commercial-simulator (VCS/Xcelium/Questa) or from-source-Verilator UVM tier, if the repo has one — license-gated or RAM-heavy, so it degrades to a graceful skip when the simulator/toolchain is unavailable rather than failing the build | if applicable |
| `lp` | low-power/UPF example or emulation, if authored | if applicable |
| `waves` / `wave` / `gtkwave` | waveform dump (`waves`), and dump-then-open-in-GTKWave (`wave`/`gtkwave`), if authored | if applicable |
| `ci` | the comprehensive run: everything the reader can run without extra provisioning (typically `regress` + `coverage` + `formal`, whatever the repo has) | required |
| `clean` | remove build/sim/coverage artifacts | required |

Everything else each repo already has — per-config test matrices, metrics/
dashboard collection, Docker/Railway/cloud-swarm automation, docs/PDF
generation, per-block micro-smokes, waveform drift-guards, and so on — keeps
its existing name exactly as-is. This document does not touch it, and does not
ask any repo to add capability it doesn't have.

## Conventions

- Hyphens, not underscores, in multi-word target names going forward
  (`coverage-summary`, not `coverage_summary`). Existing underscore names are
  kept (never renamed out from under a script that calls them); a new
  hyphenated alias may be added alongside.
- `COV_MIN` is the coverage-floor variable name wherever a coverage floor is
  enforced.
- Every target that depends on an optional external tool (`sby`, `yosys`,
  `verible-verilog-lint`, `gtkwave`, `verilator_coverage`, a commercial UVM
  simulator, …) checks for it and **exits 0 with a one-line skip message**
  rather than failing the build.
- `make` with no target prints `help` and does nothing else.

## Non-goals

This does not standardize CI YAML, container images, which simulator a given
repo uses, or what `check`/`regress`/`ci` include beyond the floor above (a
repo with ten DV environments folds all ten into its own `regress`/`ci`, per
its own judgment) — only the `make <target>` *names* a person (or another
Claude session) can rely on being present and meaning roughly the same thing
across every repo in this family.
