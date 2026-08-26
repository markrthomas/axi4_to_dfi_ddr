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

# 3. Target architecture

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

# 4. Phase 0 — Preserve the known-good swarm

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

---

# 5. Phase 1 — Establish `axi4_to_dfi_ddr` baseline

**Status: complete.** `doc/INITIAL_ARCHITECTURE_BASELINE_REPORT.md` records the analysis-only baseline, open-source verification evidence, known limitations, and the reference-swarm discovery required before Phase 2.

The baseline established:

## Repository structure

- RTL directories/files
- testbench
- UVM
- scripts
- Makefiles
- simulator configuration
- CI/GitHub Actions
- documentation

## Hardware architecture

- AXI4 interface
- internal transaction architecture
- DFI interface
- DDR architecture
- clock domains
- resets
- FIFOs
- state machines
- data paths
- CDC

## Verification architecture

- UVM environment
- agents
- drivers
- monitors
- sequencers
- scoreboards
- reference models
- assertions
- coverage
- tests
- regression scripts

## Baseline evidence

Determine and record:

```text
compile       PASS / FAIL / NOT AVAILABLE
lint          PASS / FAIL / NOT AVAILABLE
basic sim     PASS / FAIL / NOT AVAILABLE
regression    PASS / FAIL / NOT AVAILABLE
coverage      AVAILABLE / NOT AVAILABLE
```

The coverage export defect discovered during baseline review was corrected after explicit approval. Do not begin RTL or verification feature work until the Phase 2 entry decisions are approved.

---

# 6. Phase 2 — Create swarm infrastructure

Proposed structure:

```text
axi4_to_dfi_ddr/
|
+-- swarm/
|   +-- PLAN.md
|   +-- ARCHITECTURE.md
|   +-- BACKLOG.md
|   +-- STATUS.md
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

The actual directory structure should be adapted after inspecting the repository and the reference swarm.

---

# 7. Agent roles

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

# 8. Git strategy

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

# 9. Persistent swarm knowledge

## `ARCHITECTURE.md`

Document discovered architecture and interfaces.

## `BACKLOG.md`

Maintain prioritized work.

Initial example:

### P0

- [x] Establish baseline (`doc/INITIAL_ARCHITECTURE_BASELINE_REPORT.md`)
- [ ] Understand AXI4
- [ ] Understand DFI
- [ ] Understand DDR architecture

### P1

- [ ] AXI4 protocol verification
- [ ] DFI protocol verification
- [ ] Basic write path
- [ ] Basic read path

### P2

- [ ] Burst testing
- [ ] Backpressure
- [ ] Random traffic
- [ ] Error handling
- [ ] Coverage

### P3

- [ ] Stress testing
- [ ] Performance
- [ ] Corner cases

## `STATUS.md`

Example:

```text
Agent       Task             Status
-----------------------------------------
Copilot     Architecture     DONE
Codex       AXI4 RTL         WORKING
K3          DFI analysis     WORKING
Claude      UVM              WAITING
Regression  Baseline         PASS
```

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

# 10. Model independence

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

# 11. Verification quality gates

A task is not complete because the RTL compiles.

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

# 12. Model benchmark

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

# 13. Railway

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

# 14. Security

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

# 15. First milestone

The first milestone is NOT to implement the DDR controller.

The first milestone is:

> Establish a functioning multi-model swarm with a reproducible repository baseline.

Success means:

```text
Codex CLI
   |
   v
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
Create backlog
   |
   v
Design first agent tasks
   |
   v
Launch agents
   |
   v
Isolated branches
   |
   v
Tests / PRs
   |
   v
Human review
```

---

# 16. First Codex mission

The first Codex session should be analysis-only.

Prompt:

> Read `SWARM_PLAN.md`. Do not modify RTL or verification code. Inspect the `axi4_to_dfi_ddr` repository and produce an initial architecture and baseline report. Identify the repository structure, AXI4 architecture, DFI/DDR architecture, verification environment, available simulations/regressions, and current failures. Also identify what information we need from the existing `axi-on-ucie-to-mem` repository before implementing the swarm. Create/update only planning documentation required by this mission. Do not implement swarm infrastructure yet.

After this report, review it manually before allowing Codex to proceed.

---

# 17. Development philosophy

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
