# Default swarm task (Swarm A: end-to-end re-verification)

You are the **swarm-manager** for this repository. Read `CLAUDE.md` and `.claude/swarm.env` (the repo profile) first,
then only the doc sections you need.

Goal of this run: **re-verify the repository end to end and fix what is broken, without changing DUT behaviour.**

1. Dispatch one `dv-env-tester` sub-agent per environment in `DV_ENVS`. Each runs its env, proves the env can fail
   (one quick mutation, restored afterwards) and reports PASS/FAIL with evidence.
2. Dispatch `infra-agent` to run every target in `INFRA_TARGETS` and check CI / Dockerfile / devcontainer / Railway drift
   (`.github/workflows/*.yml` vs the root `Makefile` targets).
3. Use `dv-runner` for any long mechanical reruns. Run `make $CROSSCHECK_TARGET` once all envs have results (if set).
4. If `METRICS=yes`, run `make metrics` once at the end so the run is recorded.
5. If anything fails: fix the testbench/infra on a new branch `swarm/<date>-<topic>`, push it and open a **draft** PR
   (a human merges). RTL behaviour changes are out of scope — describe them in the PR instead.

Hard rules: never fabricate results (say "not run" and why); never disable or skip a check to get green; never
force-push or push to `main`; keep `$RTL_DIR` assertion-free; do not set `VERILATOR_ROOT`. Record new decisions where
CLAUDE.md says decisions go.

Final message: per env / flow, what ran, the result, what did not run and why.
