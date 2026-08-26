# Multi-Model AI Swarm Plan — `axi4_to_dfi_ddr`

## 1. Objective

Build a multi-agent engineering swarm for the `axi4_to_dfi_ddr` repository.

The swarm will use:

- **GitHub** as the shared source of truth
- **GitHub Copilot** as the initial orchestration/cloud-agent layer
- **OpenAI Codex** as an RTL/architecture/debug specialist
- **Kimi K3** as a DFI/DDR specialist
- **Claude** as a DV/UVM specialist
- Git branches/worktrees and pull requests as the integration mechanism
- Automated compilation, simulation, regression, and review as quality gates

The existing `axi-on-ucie-to-mem` Claude Code + Railway swarm is the reference implementation. Do not modify that project while building this one.

---

## 2. Guiding principles

1. **Do not change RTL or verification code until the baseline is understood.**
2. **Use the existing `axi-on-ucie-to-mem` swarm as a reference, not as a blind template.**
3. **Keep model assignments interchangeable.**
4. **No agent merges directly to `main`.**
5. **Every substantive change must have tests/evidence.**
6. **Compilation is not verification.**
7. **Independent review is required for important architectural changes.**
8. **Persistent swarm knowledge belongs in version-controlled files.**
9. **Secrets/API keys must never be committed.**
10. **Start simple; add Railway only if persistent workers/cloud execution are actually needed.**

---

# 3. Current decisions and status

| Topic | Status |
|---|---|
| Product direction | Keep the bridge simulation-oriented; prioritize CDC and verification hardening before production DDR features. |
| Baseline | Complete; see `doc/INITIAL_ARCHITECTURE_BASELINE_REPORT.md`. |
| Open-source local gates | `make -C test ci`, `make coverage`, `make cocotb`, and `make -C verification/formal all` pass in the checkpointed baseline. |
| GitHub Actions | The pushed hardening checkpoint passed CI (run `32930676667`). |
| UVM/VCS regression | Optional licensed regression. Open-source CI remains the required gate; an unavailable VCS run is reported as unavailable, not passing. |
| Reference swarm audit | Complete; the Section 5 classification records reusable mechanics and deferred infrastructure. |
| Task state | GitHub Issues are canonical. Version-controlled files retain architecture and decisions, not mirrored backlog/status state. |
| Swarm infrastructure | Minimal contracts and issue intake are implemented. Provider automation and worker deployment remain deferred. |

---

# 4. Target architecture

```text
                         GitHub
                            |
                    +-------+-------+
                    |  Coordinator  |
                    | GitHub Copilot|
                    +-------+-------+
                            |
              +-------------+-------------+
              |             |             |
              v             v             v
           Codex          Kimi K3       Claude
        RTL / AXI4       DFI / DDR       DV / UVM
              |             |             |
              +-------------+-------------+
                            |
                     Regression / CI
                            |
                            v
                       GitHub PRs
                            |
                            v
                     Human review/merge
```

GitHub is the shared state. Models are workers.

---

# 5. Phase 0 — Preserve the known-good swarm

**Status: complete (read-only audit).**

The existing repository:

`axi-on-ucie-to-mem`

contains a working Claude Code + Railway swarm.

Before implementing the new swarm, document:

- Claude configuration
- agent definitions
- prompts
- Railway services
- environment variables
- startup commands
- Git workflow
- branch strategy
- agent communication
- task management
- persistent state
- testing/regression mechanism
- PR workflow

Separate reusable swarm infrastructure from AXI/UCIe-specific knowledge.

## Reference audit classification

The reference repository was inspected read-only. No reference files, secrets, or
credentials were copied.

| Reference artifact or practice | Decision | Application here |
|---|---|---|
| Durable repository instructions and focused agent contracts (`CLAUDE.md`, `.claude/agents/`) | Adapt | Keep `.github/copilot-instructions.md` as the current durable repository guide; add narrow agent contracts only after the task-state model is approved. |
| Manager plus read-only verification/infra roles | Adapt | Preserve explicit ownership and read-only test roles, but define roles around this repository's Icarus, Verilator, cocotb, Yosys, and optional VCS flows. |
| Branch-per-task, checkpoint commits, PR-based human merge | Adapt | Use isolated branches for future agent-owned changes. Human-directed work may explicitly request a direct main push. |
| Plan-driven workflow armed by document front matter | Requires human decision | The trigger pattern is reusable, but it must not be enabled until task authorization, required checks, provider authentication, and PR permissions are explicitly approved. |
| Reference DV gate and environment matrix | Do not adopt | Its PyUVM/SystemC/UCIe-specific commands, coverage threshold, and generated EDA artifact do not apply to this AXI4-to-DFI bridge. |
| Container image, pinned tool bundle, and memory-concurrency limits | Adapt later | Reuse only after this repository needs a reproducible containerized gate; preserve its principle of bounded parallel Verilator builds. |
| Railway batch job and daily schedule | Do not adopt initially | Local tools plus GitHub Actions are sufficient; revisit only if persistent/scheduled workers have a demonstrated need. |
| Provider-specific routing, secrets, and run metrics | Requires human decision | Provider selection, authentication, secret storage, token scope, and retention policy are operational decisions and must not be inferred from the reference. |

---

# 6. Phase 1 — Establish `axi4_to_dfi_ddr` baseline

**Status: complete.** `doc/INITIAL_ARCHITECTURE_BASELINE_REPORT.md` records the analysis-only baseline, open-source verification evidence, known limitations, and the reference-swarm discovery required before Phase 2.

The baseline established:

## Completed scope

- RTL directories/files
- testbench
- UVM
- scripts
- Makefiles
- simulator configuration
- CI/GitHub Actions
- documentation

The report captures repository structure; AXI, DFI, CDC, reset, and scheduler architecture; open-source and UVM verification environments; and baseline command evidence. The completed hardening checkpoint also adds dual-clock FIFO simulation under Icarus and Verilator, bounded FIFO data-integrity checks, and a working coverage export.

The coverage export defect discovered during baseline review was corrected after explicit approval. Do not create swarm infrastructure or begin unapproved feature scope until the Phase 2 entry decisions are approved.

---

# 7. Phase 2 — Create swarm infrastructure

**Entry criteria:**

1. **Complete:** audit `axi-on-ucie-to-mem` according to the baseline report's reference checklist and classify each artifact as adopt, adapt, do not adopt, or requiring a human decision.
2. **Complete:** keep UVM/VCS as an optional licensed regression; retain open-source CI as the required gate.
3. **Complete:** confirm the pushed GitHub Actions run completes with the intended required checks (CI run `32930676667`).
4. **Complete:** use GitHub Issues as canonical task state; retain committed architecture and decision records only.

**Implemented minimal configuration:**

- `swarm/PLAN.md`, `swarm/ARCHITECTURE.md`, `swarm/DECISIONS.md`, and
  `swarm/AGENTS.md` define the operating rules and durable context.
- `.claude/agents/` contains coordinator, RTL/CDC, and read-only DV contracts.
- `.github/ISSUE_TEMPLATE/swarm-task.yml` standardizes GitHub Issue intake.
- [Issue #1](https://github.com/markrthomas/axi4_to_dfi_ddr/issues/1) is the
  first canonical task: a true dual-clock FIFO formal model.

Proposed structure:

```text
axi4_to_dfi_ddr/
|
+-- swarm/
|   +-- PLAN.md
|   +-- ARCHITECTURE.md
|   +-- DECISIONS.md
|   +-- AGENTS.md
|
+-- .github/
|   +-- workflows/
|
+-- .claude/
|   +-- agents/
|
+-- RTL / existing project files
```

The actual directory structure must be adapted only after the entry criteria are satisfied. Start with the smallest approved subset; do not introduce Railway services until local/GitHub orchestration has demonstrated a need for persistent workers.

---

# 8. Agent roles

## Coordinator — GitHub Copilot

Responsibilities:

- maintain backlog
- decompose work
- assign tasks
- track dependencies
- prevent duplicate work
- monitor branches/PRs
- request reviews
- maintain swarm status

The coordinator should not automatically become the primary RTL developer.

---

## Codex — RTL / Architecture / Debug

Primary responsibilities:

- RTL architecture
- AXI4 implementation
- state machines
- datapaths
- RTL refactoring
- AXI protocol reasoning
- simulation/debug
- architectural code review

Codex should ask:

> Is this actually correct hardware, or merely code that compiles?

---

## Kimi K3 — DFI / DDR Specialist

Primary responsibilities:

- DFI interpretation
- DFI timing
- command/address
- read/write data paths
- initialization
- training-related behavior
- PHY interaction
- DDR corner cases
- independent architecture review

Use K3's large context capability when repository + specification + verification context needs to be considered together.

---

## Claude — DV / UVM Specialist

Primary responsibilities:

- UVM architecture
- AXI4 verification
- DFI verification
- sequences
- drivers
- monitors
- scoreboard
- reference model
- assertions
- coverage
- constrained-random testing

Use the existing Claude/Railway implementation as a proven DV workflow reference.

---

## Regression / Debug Agent

Initially this may be implemented with Codex or Copilot rather than a separate model.

Responsibilities:

```text
compile
   |
   v
lint
   |
   v
directed tests
   |
   v
simulation
   |
   v
regression
   |
   v
coverage
```

The regression agent's job is to find failures and report them clearly.

---

# 9. Git strategy

No agent should directly merge to `main`.

Preferred pattern:

```text
main
 |
 +-- swarm/codex-rtl
 +-- swarm/k3-dfi
 +-- swarm/claude-dv
 +-- swarm/regression
```

Normal workflow:

```text
Issue
  |
  v
Agent
  |
  v
Branch/worktree
  |
  v
Implementation
  |
  v
Tests
  |
  v
Pull Request
  |
  v
Review
  |
  v
Merge
```

Avoid having multiple agents modify the same files simultaneously unless the coordinator explicitly manages the dependency.

---

# 10. Persistent swarm knowledge

## `ARCHITECTURE.md`

Document discovered architecture and interfaces.

## GitHub Issues

GitHub Issues are the canonical task backlog, assignment, and status system.
Every swarm task must identify its issue, expected evidence, owning branch, and
reviewer. Do not mirror issue state into committed Markdown files.

## `DECISIONS.md`

Record important architectural conclusions so agents do not repeatedly rediscover them.

Example:

```text
Decision #003

DFI data-width conversion occurs in module XYZ.

Reason:
...

Implication:
...
```

## `AGENTS.md`

Define:

- agent roles
- rules
- expected outputs
- branch rules
- testing requirements
- review requirements
- escalation rules

---

# 11. Model independence

Do not hard-code the engineering process around a particular model.

Define agent contracts around:

```text
ROLE
TASK
INPUT
OUTPUT
TEST
REVIEW
```

rather than model-specific behavior.

This allows:

```text
DFI = K3
```

to later become:

```text
DFI = Codex
```

without redesigning the swarm.

---

# 12. Verification quality gates

A task is not complete because the RTL compiles.

The required gate is the repository's open-source CI flow. VCS/UVM is an
optional licensed regression: run it when the licensed environment is available,
but report an unavailable run distinctly rather than converting it into a pass.

Preferred progression:

```text
Syntax
  |
Compile
  |
Lint
  |
Directed test
  |
Protocol assertions
  |
Random test
  |
Regression
  |
Coverage
  |
Independent review
```

For example, "implement AXI burst handling" is incomplete until appropriate burst lengths, backpressure, outstanding transactions, boundaries, reset, read/write interaction, and error cases have been considered and tested.

---

# 13. Model benchmark

Before permanently assigning every role, benchmark the models on the actual repository.

Give Codex, K3, Claude, and Copilot comparable tasks:

1. Analyze repository architecture.
2. Explain AXI4 architecture.
3. Identify potential AXI4 protocol problems.
4. Explain DFI architecture.
5. Design a DFI verification strategy.
6. Review an RTL module.
7. Debug a failing simulation.
8. Design a UVM environment.
9. Review another agent's proposed change.

Record:

```text
Model       Correctness   Completeness   Code quality   Debugging
-----------------------------------------------------------------
Codex
K3
Claude
Copilot
```

Use actual results to determine final role assignments.

---

# 14. Railway

Railway is not required for the initial implementation.

First establish:

```text
WSL
 |
Codex CLI
 |
GitHub
 |
Copilot/cloud agents
 |
K3
 |
Claude
```

Once this works, evaluate whether persistent Railway workers provide enough value to justify the additional infrastructure.

If needed, reproduce the proven Railway architecture from `axi-on-ucie-to-mem`.

---

# 15. Security

Never commit:

- GitHub tokens
- OpenAI API keys
- Kimi API keys
- Claude API keys
- Railway credentials
- SSH private keys
- other secrets

Use environment variables and appropriate GitHub/cloud secret storage.

Agents must not print or expose secrets in logs, PRs, or swarm status files.

---

# 16. Initial milestone

The initial completed milestone was not to implement the DDR controller or swarm infrastructure. It was:

> Establish a reproducible repository baseline and obtain human approval for the next swarm phase.

Success means:

```text
Read SWARM_PLAN.md
   |
   v
Analyze repository
   |
   v
Establish baseline
   |
   v
Create architecture report
   |
   v
Human review
```

---

# 17. Completed initial analysis mission

The initial analysis-only mission is complete and its result is `doc/INITIAL_ARCHITECTURE_BASELINE_REPORT.md`. The next swarm task is the Section 5 reference audit, not RTL implementation or worker deployment.

---

# 18. Development philosophy

This is an engineering swarm, not a collection of autonomous code generators.

The human engineer remains the final authority for:

- architecture
- protocol interpretation
- verification strategy
- merging
- acceptance criteria
- security
- specification compliance

Agents should produce evidence, not just assertions of correctness.
