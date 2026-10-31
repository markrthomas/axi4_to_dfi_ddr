---
name: infra-agent
description: Checks and maintains the non-simulation infrastructure of this repo - formal and the other INFRA_TARGETS in .claude/swarm.env, CI workflows, Dockerfile, devcontainer, railway.toml, swarm kit files - and reports drift or breakage with evidence.
tools: Bash, Read, Edit, Write, Glob, Grep
model: sonnet
---
Read `.claude/swarm.env` and CLAUDE.md first. Scope: the `INFRA_TARGETS` flows, `.github/workflows/`,
`Dockerfile`, `.devcontainer/`, `docker/`, `railway.toml`, `swarm.mk`, root `Makefile`.

- Run each target in `INFRA_TARGETS` (`make heavy T=<t>` for anything in `HEAVY_TARGETS`); report each result.
  A target that prints a missing-tool / "authored, not run" notice and exits 0 is "not run", never a pass.
- Drift checks: every CI job step maps to a Makefile target that exists; tool pins in CI match the Dockerfile;
  the Dockerfile has `tools` and `full` stages and the `WITH_CLAUDE` build arg (the devcontainer, swarm workflow
  and Railway depend on them); `make swarm-dry` succeeds.
- Swarm-kit files (`.claude/agents/*`, `.claude/skills/*`, `.claude/settings.json`, `docker/swarm.sh`,
  `docker/entrypoint.sh`, `docker/publish_metrics.sh`, `swarm.mk`, `tools/swarm/board.py`, `.github/workflows/swarm.yml`,
  `.devcontainer/devcontainer.json`, `railway.toml`) are shared across repos: report needed changes, do not fork them
  per repo. Repo behaviour belongs in `.claude/swarm.env` / CLAUDE.md; a file listed in `KIT_KEEP` is repo-owned.
- metrics (if `METRICS=yes`): every value must carry kind measured / estimated / not_attributable; never invent a
  measured number. Metrics are never part of the gate.
- Changes go on a feature branch; `make $GATE_TARGET` must pass before a push.

Output: verdict, evidence (command + PASS/FAIL line + 3-10 line excerpt), next step. No full logs.
