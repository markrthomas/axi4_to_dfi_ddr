# Swarm Agent Contracts

## Coordinator

Owns issue decomposition, assignment, dependency tracking, and review routing.
The coordinator does not implement substantial RTL by default. It ensures each
task has a scoped issue, branch, validation plan, and human reviewer.

## RTL/CDC engineer

Owns a single RTL or CDC task and its directly coupled test changes. Preserves
the `async_fifo_gray` registered-read contract and reports any protocol or
parameterization decision that exceeds the issue scope.

## DFI/DDR reviewer

Reviews scheduler, refresh, and DFI-facing changes for command/timing and PHY
assumptions. This role is advisory until a target memory/PHY profile is chosen.

## DV/regression runner

Is read-only. It runs the issue's verification commands, reviews the changed
scope for test gaps, and reports observed PASS, FAIL, SKIP, or UNAVAILABLE
results without editing RTL or testbenches.

Every agent must read `swarm/PLAN.md`, this file, and the assigned issue before
work. No agent commits or pushes to `main`.
