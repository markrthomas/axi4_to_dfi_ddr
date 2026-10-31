---
name: rr-bootstrap
description: Build a minimal seeded random-regression flow (make rr-build / rr / rr-triage / rr-replay, a results.jsonl per run, a replay corpus) in a repo whose .claude/swarm.env says RR_STATUS=bootstrap. Use only when that flag is set; otherwise the flow already exists.
---
Goal: the smallest honest random regression the rest of Swarm B can drive. It must find bugs, not just exist.
Reference implementation: `dv/random/` in `markrthomas/eth-dj-to-pcie-pipe-bridge` (rr.py, corpus.json, README.md) -
copy its *shape*, not its bridge-specific knobs.

**Contract** (what rr-manager / rr-runner / rr-triage rely on - keep every name):
- `make rr-build` - build the sim once (fastest env that has a scoreboard; usually Verilator, else Icarus or cocotb).
- `make rr N=<jobs> JOBS=<parallel> [SEED=<base>]` - run N jobs with seeds `SEED+i`; writes
  `$RR_DIR/runs/<UTC ts>/results.jsonl`, one line per job:
  `{"job": i, "seed": s, "config": "<knob set>", "status": "PASS|FAIL", "signature": "<first failing check>", "log": "<path>", "repro": "<command>"}`;
  prints one summary line `rr run: <dir> seed_base=<s> jobs=<N> fail=<F>`; exits non-zero iff F > 0.
- `make rr-triage RUN=<dir>` - group FAILs by signature into clusters; print one line per cluster with count + repro.
- `make rr-replay` - rerun every `$RR_DIR/corpus.json` entry; entries marked `"fixed": true` must PASS (this is the gate).
- `$RR_DIR/runs/` is git-ignored. `$RR_DIR/README.md` documents knobs, the contract above and a stimulus backlog (B1..Bn).

**Stimulus**: drive the DUT through its existing scoreboard / golden model - never a new, weaker checker. Randomize only
what the scoreboard already checks (payload, lengths, gaps, back-pressure, enables), seeded by `+seed=N` (SV `$urandom`
seeded once) or `RANDOM_SEED` (cocotb). Determinism per seed is required: run one seed twice and compare.

**Teeth**: before declaring done, apply the `MUTATION_FILE` mutation (mutation-check skill, in your worktree) and show
`make rr N=20` reports failures with a sensible signature; restore and show it clean again.

**Finish**: set `RR_STATUS=present` in `.claude/swarm.env`; add `rr-build rr rr-triage rr-replay` to the root Makefile
`help:` lines; add a "Random regression" section to CLAUDE.md; fold `rr-replay` into the CI gate only if it runs in under
2 minutes (otherwise leave it out and say so). Branch `swarm/<date>-rr-bootstrap`, draft PR, owner merges.
If the repo has no scoreboard/golden model at all, stop and report that - a random regression without a checker is not one.
