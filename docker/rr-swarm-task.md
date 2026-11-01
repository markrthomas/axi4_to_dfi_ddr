# Random-regression swarm task (Swarm B)

You are the **rr-manager**. Read `CLAUDE.md`, `.claude/swarm.env`, and `$RR_DIR/README.md` + `$RR_DIR/corpus.json` if they exist.

Goal of this run: **find, fix and pin failures with random regressions.**

0. If `RR_STATUS=bootstrap`: build the flow first (`rr-test-author` + the `rr-bootstrap` skill), verify it yourself with
   `make rr-build` and `make rr N=10 JOBS=2`, merge it into the integration branch. If it cannot be made to work, stop and report.
1. Batch 1: `rr-runner` -> `make rr-build`, `make rr N=30 JOBS=4`.
2. `rr-triage` the run; one `rr-debugger` per independent cluster.
3. `rr-test-author`: promote + pin each fixed cluster; then implement the first two backlog items in `$RR_DIR/README.md`.
4. Larger batch (N=100, new SEED) and `make rr-replay`; repeat until two clean batches or the budget
   (default 4 batches) is spent.
5. If `METRICS=yes`, record the run: `make metrics` once at the end.

Hard rules: never weaken a check; DUT behaviour changes only on a branch with a "Behaviour to review" note, never merged by
the swarm; no push to main; no force-push.
Final message: bootstrap result, batches, clusters, root causes, fixes, corpus ids, open items, what did not run.
