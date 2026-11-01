# .claude/agents — swarm agent definitions (swarm-kit v1)

These files are **identical in every RTL/DV repo** (canonical copy: `markrthomas/eth-dj-to-pcie-pipe-bridge`).
Everything repo-specific — DV env list, gate target, RTL dir, mutation target, random-regression dir —
lives in **`../swarm.env`**, which every agent reads first. Change an agent here, then copy it to the
other repos; change a repo's behaviour in its `swarm.env` / `CLAUDE.md`, never by forking an agent.

Discovered by Claude Code (non-bare) when `docker/swarm.sh` runs. Model choice = cheapest that does the job:
coordination and mechanical work are cheap, only root-cause debugging gets the big model.

| Agent | Model | Role |
|---|---|---|
| `swarm-manager` | sonnet | Swarm A (verification): dispatches dv/infra agents, verifies claims, reports |
| `dv-env-tester` | sonnet | runs one DV env (`DV_ENVS`), cross-check + one mutation |
| `infra-agent` | sonnet | `INFRA_TARGETS`, CI/Docker/devcontainer/Railway drift |
| `dv-runner` | haiku | runs a list of commands, reports raw results |
| `rr-manager` | sonnet | Swarm B (random regression): loop, status board, merges worker branches |
| `rr-runner` | haiku | builds + runs random batches (`make rr`) |
| `rr-triage` | sonnet | clusters failures, DUT vs TB classification |
| `rr-debugger` | opus | root-causes one cluster, fixes TB / writes up DUT |
| `rr-test-author` | sonnet | pins repros in the corpus, grows stimulus; bootstraps the rr flow when `RR_STATUS=bootstrap` |

Default tasks: `../../docker/swarm-task.md` (Swarm A), `../../docker/rr-swarm-task.md` (Swarm B).
All agents start from `../../CLAUDE.md` + `../swarm.env` and return "verdict + evidence + next step" (no log dumps).
Sub-agents cannot spawn sub-agents in non-interactive runs, so `docker/swarm.sh` starts the top-level session AS the
manager (`--agent swarm-manager`, or `rr-manager` for `rr-swarm-task.md`).
`dv-env-tester`, `rr-debugger` and `rr-test-author` run in their own git worktrees (`isolation: worktree`).
Shared skills: `../skills/` (`board-report`, `mutation-check`, `rr-bootstrap`). Headless Bash permissions: `../settings.json`.
Repo-only extra agents (not part of the kit) may sit beside these; list them in the repo's `CLAUDE.md`.
