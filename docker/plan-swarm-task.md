# Plan-driven swarm task

You are the **swarm-manager**. Read `CLAUDE.md`, `.claude/swarm.env`, then **`docs/SWARM_PLAN.md`** - the owner's plan
for this run (front-matter `status: ready`). Implement exactly that plan; nothing outside it.

1. Branch `swarm/<date>-plan` (or the branch the plan names). Work through the plan's items in order, one logical
   commit per item; dispatch `dv-env-tester` / `infra-agent` / `dv-runner` / rr-* workers where an item needs them.
2. After each item: `make $GATE_TARGET` must pass; quote the PASS lines. Push incrementally; open a **draft** PR early
   so an interrupted run loses at most the last item; mark it "PARTIAL - resume needed" if you run out of budget.
3. An item that would change DUT behaviour, weaken a check, or that the plan leaves ambiguous: do not guess - stop
   that item, write the question in the PR, continue with the next independent item.
4. When done: set the plan's front-matter to `status: done` (on the branch) and list per item what shipped, what
   ran (with evidence) and what did not run and why.

Hard rules: never push to `main`, never force-push, never merge; never fabricate results; never weaken or skip a check.
