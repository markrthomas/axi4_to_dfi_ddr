---
name: mutation-check
description: Prove a DV environment can fail by applying one small RTL mutation in an isolated worktree, confirming it FAILs for the right reason, and restoring the file exactly. Use before trusting any green result from a DV env.
---
A green run only means something if the env goes red when the DUT is wrong. Do this in your own git
worktree; never mutate `$RTL_DIR` in the main checkout, and never run it while another agent shares your tree.
`RTL_DIR`, `MUTATION_FILE` and `MUTATION_HINT` come from `.claude/swarm.env`.

1. Baseline: run the env (`make <env>`) and record the PASS line. If it does not pass unmutated, stop and report that.
2. Mutate ONE thing, small and deterministic. Default: `MUTATION_HINT` applied to `MUTATION_FILE`. If those are
   unset, pick one datapath operation that the env's scoreboard must observe (an off-by-one on a length/count,
   an inverted valid/ready qualifier, one corrupted data bit) and say why you chose it. Note the exact diff (`git diff $RTL_DIR`).
3. Rerun the same env. Expected: FAIL. Check the failing check is the one the mutation should trip (scenario,
   field, scoreboard or SVA name in the log), not a harness or build error. A compile error is not a pass for this test.
4. Restore the file exactly (`git checkout -- <file>`), then confirm `git diff $RTL_DIR` is empty and rerun once
   to see PASS again.
5. Report: env, baseline PASS line, mutation diff, failing check with the log path, restore confirmation.

Headless runs check every command before it runs, and refuse some shapes. Keep each step a separate, plain command:
- Heavy envs (`HEAVY_TARGETS`): `make heavy T=<env>`, never a bare `flock`. No `$?`, `$(...)`, redirects, or reads under `/tmp`.
- Make the mutation with the Edit tool, not `sed -i`; restore with `git checkout -- <file>` on its own line.
- `git diff`, `git status --short`, and the PASS/FAIL `grep` are each their own command.
- Your worktree is deleted when you finish, so the manager cannot open your logs. Paste the verbatim PASS/FAIL
  lines, the mutation diff and the failing check names in your report instead of citing paths only.

If the mutated run still passes, that is a finding: the env has a hole. Report it; do not tweak the mutation
until something fails, and never weaken or skip a checker to make results look right.
