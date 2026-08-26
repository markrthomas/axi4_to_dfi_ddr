# Initial Architecture and Baseline Report

**Repository:** `axi4_to_dfi_ddr`
**Baseline commit:** `621eda8` (`rtl: add JEDEC auto-refresh (REF) command + tRFC hold to MC scheduler`)
**Assessment date:** 2026-08-25
**Mission boundary:** analysis and planning only. No RTL or verification source was changed, and no `swarm/` infrastructure was created.

`doc/SWARM_PLAN.md` was present as an untracked planning file when this assessment began. It was read but not modified.

## 1. Executive summary

This is a compact, parameterized AXI4-slave to simplified DFI bridge. It has two asynchronous clock domains and four Gray-code asynchronous FIFOs. The AXI front end supports a deliberately narrow subset of AXI4: full-width INCR transfers, default maximum four-beat read and write bursts, with reads constrained to one DRAM row. The DFI side is a single-transaction, single-phase, open-page SDRAM-style scheduler; it is not yet a production DDR controller or a PHY-specific DFI integration.

The open-source directed baseline is healthy: the Icarus/Verilator/Yosys CI target passes, the cocotb suite passes 7/7, and both local SymbiYosys FIFO tasks pass. No RTL functional simulation failure was observed. The VCS/UVM regression cannot be compiled locally because VCS is unavailable. The Verilator coverage target had a reporting defect: it exited zero without producing the `coverage.info` artifact expected by CI because it supplied an incorrect relative path after changing into the coverage directory. The Yosys synthesis sanity target is clean of out-of-range-select warnings after internal packed-request defaults were made width-derived.

The existing `axi-on-ucie-to-mem` repository is a sibling directory, but it was not modified or used as an implementation template in this mission. Section 8 defines the precise information to obtain from it before Phase 2 of the swarm plan.

## 2. Repository structure

| Path | Purpose |
|---|---|
| `src/` | Verilog-2001 RTL, a self-contained dual-clock testbench, four parameter smokes, and elaboration-negative test tops. |
| `src/axi4_to_dfi_bridge.v` | Integration top; validates parameters and connects the AXI/CDC front end to the DFI adapter. |
| `src/axi4_bridge_frontend.v` | AXI acceptance, AW/W pairing, local error responses, response ordering counters, and all four CDC FIFO instances. |
| `src/cdc_fifo_lib.v` | `cdc_sync` two-flop synchronizer and `async_fifo_gray` FIFO library. |
| `src/dfi_adapter.v` | DFI-facing wrapper: optional init-start pulse, tied update/low-power requests, and scheduler instantiation. |
| `src/mc_dfi_scheduler.v` | DFI-clock open-page scheduler, command/data timing, read return handling, and optional refresh. |
| `test/Makefile` | Primary open-source Icarus simulation, elaboration, lint, Yosys synthesis, and legacy formal targets. |
| `cocotb/` | Python/cocotb AXI driver and simplified PHY model; seven OSS tests. |
| `uvm_dv/` | VCS + UVM 1.2 environment, sequences, scoreboarding, functional coverage, and six named tests. |
| `formal/` | Legacy Yosys bounded FIFO safety harness invoked by `make -C test formal-fifo`. |
| `verification/formal/` | SymbiYosys BMC and cover harness for the FIFO wrapper. |
| `syn/` | Yosys elaboration/synthesis sanity script and commented timing/CDC constraint hints. |
| `.github/workflows/ci.yml` | GitHub Actions jobs for the open-source directed suite, coverage export, and cocotb. |
| `doc/` | Design specification, full-functionality roadmap, swarm plan, and this report. |

There is no committed `swarm/` directory, GitHub swarm workflow, versioned agent-role definition, or task/status/backlog infrastructure. A local `.claude/settings.local.json` exists, but it is an allow-list of local command permissions rather than a committed multi-agent design.

## 3. Hardware architecture

### 3.1 Top-level partitioning and parameters

`axi4_to_dfi_bridge` is a thin integration wrapper around `axi4_bridge_frontend` and `dfi_adapter`. Default configuration is 32-bit AXI addresses, 64-bit AXI/DFI data, 4-bit AXI IDs, 18-bit DFI address, 3-bit DFI bank, and FIFO depth 8.

The top-level parameter checks enforce equal AXI and DFI data widths, byte-integral data width, matching mask width, a power-of-two FIFO depth of at least two, valid address-map field widths, bounded counters, and a read-response FIFO depth sufficient for the configured maximum read burst. There is no data-width conversion block.

### 3.2 Clock, reset, and CDC architecture

| Domain | Clock / reset | Responsibility |
|---|---|---|
| AXI | `axi_aclk`, active-low `axi_aresetn` | AXI handshakes, AW/W pairing, local AXI errors, and AXI-side response delivery. |
| DFI | `dfi_clk`, active-low `dfi_rst_n` | Request dequeue, scheduling, DFI command/data presentation, and response generation. |

`async_fifo_gray` uses binary storage pointers, Gray-coded crossed pointers, two-flop `cdc_sync` synchronizers, and a registered read-side data contract: `rd_empty == 0` means `rd_data` is stable until consumed. The bridge instantiates four independent FIFOs:

```text
AXI domain                                        DFI domain
AW + W -> write-request FIFO  ----------------->  scheduler
AR     -> read-request FIFO   ----------------->  scheduler
B      <- write-response FIFO <-----------------  scheduler
R      <- read-response FIFO  <-----------------  scheduler
```

The scheduler separately synchronizes `dfi_init_complete` into the DFI domain and does not pop requests until it is observed asserted. The two resets are independent; no reset-domain-crossing proof or target-specific CDC constraints are present.

### 3.3 AXI4 architecture and supported subset

The front end accepts AW and W independently, retains either side in a one-entry holding register, and packs each valid write beat as `{WLAST, ID, address, data, strobe}`. An AXI write burst produces one DFI request per W beat and one B response after the final beat. Legal traffic is:

- `AWBURST` / `ARBURST == INCR` only;
- full-bus `AWSIZE` / `ARSIZE` only;
- `AWLEN <= C_MAX_WRITE_AWLEN` and `ARLEN <= C_MAX_READ_ARLEN` (both default to 3, i.e. four beats);
- read bursts must remain within one decoded DRAM row; and
- `WLAST` must exactly match the accepted write-burst beat position.

Unsupported accepted shapes receive local `SLVERR` responses. The AXI sideband fields are accepted at the port boundary but are not propagated through the internal request format; B/R user outputs are tied to zero. The RTL has no explicit alignment check, and the support policy for narrow, unaligned, FIXED, WRAP, exclusive, and cross-ID behavior is incomplete.

Normal B/R responses return through the CDC FIFOs. One local-error response can be held or pending per channel; `b_legal_outstanding` and `r_legal_outstanding` delay a local error behind older legal responses. This is a useful limited ordering mechanism, but it is not a general response-queue architecture and needs formal/protocol review before AXI feature expansion.

### 3.4 DFI and DDR-side architecture

`dfi_adapter` ties `dfi_ctrlupd_req`, `dfi_phyupd_req`, and `dfi_lp_ctrl_req` low. It can emit `dfi_init_start` for `DFI_INIT_START_CYCLES`, but update, low-power, training, calibration, and init-complete protocol behavior are not state-machine implementations.

`mc_dfi_scheduler` processes one request at a time, with writes preferred over reads when both request queues are nonempty. It decodes the low AXI address bits as `{bank,row,column}`, maintains an open-row bit and row address for every bank, and schedules:

```text
row closed:       ACT -> tRCD wait -> RD/WR CAS
row hit:                              RD/WR CAS
row conflict:     PRE -> tRP wait -> ACT -> tRCD wait -> RD/WR CAS
```

Implemented timing controls include `MC_T_RP`, `MC_T_RCD`, `MC_T_RAS`, `MC_T_WR`, `MC_CL`, `MC_RD_DV_MAX`, and `DFI_WRITE_ACK_CYCLES`. Reads assert `dfi_rddata_en`, wait for the configured CAS delay and `dfi_rddata_valid`, then push ID/data/last to the R-response FIFO. A read-data timeout produces `SLVERR` for the affected beat and any remaining burst beats.

Refresh is disabled by default. With `MC_REFRESH_INTERVAL > 0`, the scheduler blocks new dequeues, walks all banks to precharge open rows while respecting the implemented PRE guards, issues a REF command, and holds for `MC_T_RFC`. This remains a simplified policy: no selected DRAM timing profile, refresh postponement/pull-in policy, bank groups, `tRC`, `tRRD`, `tFAW`, `tCCD`, `tWTR`, `tRTP`, mode-register flow, or full initialization sequence exists.

The DFI presentation is single phase. It emits command/address/bank, `act_n`, chip select, CKE/ODT, write data/mask/enable, and read-data enable; it does not implement P0-P3 phase lanes or a selectable PHY clock ratio. There is no DDR pin-level model or persistent DRAM memory model in the default verification environment.

## 4. Verification architecture

### 4.1 Self-contained Icarus environment

`src/tb_axi4_to_dfi_bridge.v` supplies 50 MHz AXI and approximately 71 MHz DFI clocks, independent resets, a minimal PHY read-return model, AXI drivers/tasks, command counters, response backpressure checks, and deterministic LFSR stress. Its PHY model returns an address-derived constant rather than storing write data, so it validates bridge transport/control behavior, not full memory data coherence.

The main test checks initialization gating, supported and illegal traffic, legal-before-local-SLVERR ordering, B/R stability under backpressure, response FIFO fill while BREADY/RREADY are low, multiple read IDs, PRE/ACT/CAS behavior, and deterministic writes-then-reads stress. The parameter smokes cover FIFO depth 16, zero cycle timing settings, refresh/`tRFC`, and `tRAS`/`tWR`. Seven negative elaboration tops check parameter guards.

`tb_async_fifo_gray.v` is a dedicated dual-clock FIFO test invoked by `make -C test run-fifo` and the CI target. It verifies usable depth, registered-head stability while stalled, and ordered concurrent traffic. It found and verified the correction of one-entry-early `wr_full` assertion in `async_fifo_gray`. `make -C test run-fifo-verilator` runs the same test under Verilator's timing engine.

### 4.2 cocotb environment

`cocotb/env.py` has a lightweight AXI4 driver and an address-queue PHY model. `cocotb/test_dfi_bridge.py` contains seven tests:

1. single write/read;
2. four-beat burst write/read;
3. AW before W;
4. W before AW;
5. B-channel backpressure;
6. R-channel backpressure; and
7. illegal FIXED write burst returning `SLVERR`.

This is an independent OSS test style but uses the same simplified address-formula PHY behavior as the Verilog testbench.

### 4.3 UVM environment

The UVM environment targets VCS with bundled UVM 1.2. It contains:

- an active AXI agent (sequencer, driver, and monitor);
- a passive DFI command monitor/agent;
- a scoreboard for AXI completion response and read data against the PHY formula;
- functional covergroups over read/write burst type, length, and response; and
- `smoke_test`, `mc_cmd_test`, `burst_rw_test`, `fifo_depth_test`, `slverr_test`, and `stress_test`.

The DFI monitor decodes and counts PRE/ACT/read-CAS/write-CAS for the command-count test. It is not connected to a timing-aware DFI scoreboard. The functional coverage has no local collection report in the Makefile, and the UVM flow is not executable in this environment without VCS. There are no AXI/DFI SystemVerilog assertion files in the repository.

### 4.4 Formal and synthesis checks

`make -C test formal-fifo` runs the legacy Yosys BMC FIFO wrapper. `make -C verification/formal all` runs SymbiYosys BMC and cover to depth 55. Both are useful FIFO safety evidence, but the wrapper reduces the crossing to a single-clock scenario and deliberately assumes host-safe use, including no simultaneous push and pop. They do not prove metastability behavior, true dual-clock ordering, or no loss/duplication/reordering for arbitrary FIFO traffic.

`syn/yosys.ys` is an elaboration/optimization sanity script, not an implementation or timing signoff flow. `syn/constraints.sdc` is only commented guidance. No lint waiver policy, CDC/RDC analysis, STA, or target memory/PHY integration flow is present.

## 5. Simulations, regressions, and baseline evidence

All commands below were run from this checkout on the stated baseline. `PASS` means the command returned success; it is not a claim of production protocol closure.

| Gate | Command | Result | Evidence / scope |
|---|---|---|---|
| Compile | `make -C test build` (also exercised by CI) | PASS | Icarus compiles top RTL plus the self-contained testbench. |
| Lint | `make -C test lint-verilator` | PASS | Verilator `--lint-only`; width/unused/declaration-file diagnostics are waived by the target. |
| Basic simulation | `make -C test run` | PASS | Main dual-clock directed testbench passed. |
| Directed regression | `make -C test ci` | PASS | Main test, four parameter smokes, seven expected elaboration failures, Verilator lint, Yosys sanity, and legacy FIFO BMC all completed. |
| cocotb regression | `make -C cocotb` | PASS | Seven tests passed. Local run used cocotb 1.9.2 and `/usr/bin/iverilog` 11.0; CI pins cocotb 1.8.1. |
| SymbiYosys FIFO BMC | `make -C verification/formal all` | PASS | Safety BMC passed to depth 20 and reachability cover to depth 55; single-clock/assumption-limited scope. |
| UVM regression | `make -C uvm_dv run-all` | NOT AVAILABLE | Fails before compile: `vcs: No such file or directory`. This is an environment/license gap, not an observed RTL/UVM functional failure. |
| Synthesis sanity | `make -C test syn-check` | PASS AFTER CORRECTION | Width-derived defaults for internal request/response payloads eliminate the earlier out-of-range-select warnings. |
| Coverage | `make coverage` | PASS AFTER CORRECTION | The prior target built/runs and left `obj_dir_cov/coverage.dat`, but did not export repository-root `coverage.info`. The Makefile now exports from `coverage.dat` after entering `obj_dir_cov`, verifies the result, and produced a nonempty `coverage.info` in this checkout. |

GitHub Actions runs `make -C test ci`, `make coverage`, and `make cocotb` on push and pull request to `main`. It does not run the VCS/UVM regression or the SymbiYosys suite. Its coverage artifact upload uses `if-no-files-found: ignore`, so the current missing `coverage.info` will not necessarily fail the workflow.

## 6. Current failures, warnings, and baseline risks

### Executed failure: VCS/UVM unavailable

`make -C uvm_dv run-all` exits 2 because `vcs` is not on `PATH`. The available UVM environment therefore has no current local compile, simulation, coverage, or regression evidence. Obtain a licensed VCS environment or define an intentionally supported alternate simulator before treating the UVM suite as a swarm quality gate.

### Corrected failure formerly masked as success: coverage artifact

`make coverage` produced `obj_dir_cov/coverage.dat` but no repository-root `coverage.info`. The target changed into `obj_dir_cov`, then passed `obj_dir_cov/coverage.dat` to `verilator_coverage`; that resolved to the nonexistent `obj_dir_cov/obj_dir_cov/coverage.dat`. `verilator_coverage` returned success without producing output, and the Makefile printed a misleading success message. The target now exports `coverage.dat` from within `obj_dir_cov` and requires a nonempty `../coverage.info`.

### Corrected warning-bearing success: Yosys synthesis sanity

`make -C test syn-check` initially reported out-of-range part-select warnings because the standalone defaults for `WREQ_W`, `RREQ_W`, and response payload widths were smaller than their default AXI field layouts. The top-level overrides masked this during simulation, but generic Yosys module analysis exposed the inconsistency. The defaults now derive from the AXI widths in each affected submodule, and the out-of-range warnings are absent.

### Documentation inconsistency: refresh capability

The current RTL and `doc/FULL_FUNCTIONALITY_PLAN.md` state that refresh performs PRE walk, REF, and `MC_T_RFC` hold. `doc/DESIGN_SPEC.md` still contains an older statement that a JEDEC-accurate REF command and `tRFC` bookkeeping are not in the block. Resolve this contradiction before assigning DFI/DDR work so agents have one authoritative capability statement.

### Coverage and verification limitations (not command failures)

- No current simulation proves data persistence because the PHY models derive read data from address instead of a write-updated memory model.
- Formal FIFO evidence is not a multi-clock CDC proof and lacks data-integrity/order properties.
- The UVM constrained-random, scoreboard, coverage, and DFI monitor have not been run in this baseline.
- No protocol assertion suite, DFI timing BFM, CDC/RDC tool run, or timing signoff is present.
- The current CI tool/version set differs from the local cocotb run; reproducible tool version capture is incomplete.

## 7. Architecture conclusions for future task assignment

These are planning observations, not implementation tasks authorized by this mission.

| Area | Suitable initial specialty | Reason |
|---|---|---|
| AXI front end and response ordering | RTL / AXI engineer | Limited AXI subset, local-error ordering, AW/W pairing, and burst constraints are concentrated in `axi4_bridge_frontend.v`. |
| FIFO/CDC hardening | RTL plus formal/DV review | All inter-domain traffic depends on one reusable FIFO design and its registered-read contract. |
| DFI scheduler and refresh | DFI / DDR engineer | Command encoding, page policy, timing guards, refresh policy, PHY assumptions, and missing JEDEC timings are concentrated in `mc_dfi_scheduler.v` and `dfi_adapter.v`. |
| UVM, assertions, coverage, and regressions | DV engineer | An existing UVM skeleton needs a runnable simulator, a real reference model, coverage reporting, and stronger protocol/timing checkers. |
| CI / failure reporting | Regression engineer | Current open-source directed flow is usable, but coverage export, tool versioning, and formal inclusion need gate ownership. |

Do not begin feature development before the human review decides whether the bridge remains a simulation-oriented prototype or is being advanced toward a named DRAM/PHY target. That choice determines the AXI support policy, DDR timing profile, DFI revision/phase mode, clock ratio, reset sequence, and meaningful verification model.

## 8. Required discovery from `axi-on-ucie-to-mem` before implementing the swarm

The reference swarm must be examined as a source of reusable process mechanics, not copied blindly. Capture only secret-safe configuration: environment-variable names and where secrets are injected, never values, tokens, private keys, or exported credentials.

| Information to capture | Questions to answer | Reusable or project-specific? |
|---|---|---|
| Repository and GitHub setup | Remote/organization, protected branches, required checks, issue/PR templates, labels, project board, environments, and human approval points. | Mostly reusable. |
| Agent definitions and prompts | `CLAUDE.md`, `.claude/agents/`, role prompts, input/output contract, task decomposition, review prompts, context limits, escalation, retry, and termination rules. | Framework reusable; UCIe technical prompts are project-specific. |
| Coordinator and task state | How tasks are assigned, claimed, updated, deduplicated, retried, and closed; canonical files or GitHub entities used as state; ownership/concurrency rules. | Mostly reusable. |
| Persistent swarm files | Exact structure and examples of plan, backlog, status, decisions, architecture, and agent instructions; which files are committed and who may edit each. | Structure reusable; content project-specific. |
| Railway deployment | `railway.toml`, service definitions, images/Dockerfiles, start commands, worker lifecycles, volumes, health checks, logging, restarts, and local-vs-cloud dispatch policy. | Infrastructure mechanics reusable; service sizing and code project-specific. |
| Environment and secret handling | Required variable names, secret-store mapping, local bootstrap method, redaction behavior, rotation/ownership, and confirmation that no secret is written to state or logs. | Reusable security practice. |
| Model invocation and communication | How Claude/Copilot/Codex/other workers are called, authenticated, handed task context, notified of results, and prevented from concurrent edits. | Mostly reusable. |
| Worktree and branch lifecycle | Branch names, worktree creation/removal, rebase/update policy, commit conventions, PR creation, review assignment, merge/revert authority, and recovery from failed branches. | Reusable. |
| Quality gates and artifacts | Exact commands, tool images/licenses, timeout/retry policy, test selection, regression reports, coverage/formal artifacts, log retention, and PR status mapping. | Framework reusable; AXI/DFI gates must be defined here. |
| Operational evidence | A recent successful end-to-end task trace, including dispatch, worker output, CI result, review, merge, and post-merge state update. | Reusable process evidence. |

Before any Phase 2 implementation, produce a comparison that labels every reference artifact as one of: **adopt unchanged**, **adapt**, **do not adopt**, or **requires a human decision**. In particular, decide whether persistent Railway workers are justified; the swarm plan explicitly permits starting with local tools plus GitHub and adding Railway only when persistence provides demonstrated value.

## 9. Recommended human review checkpoints before Phase 2

1. Accept this baseline and decide whether to make the open-source directed suite the initial required gate.
2. Decide how the VCS/UVM flow will be licensed, run, or marked optional; do not call it a passing regression until executed.
3. Confirm the corrected coverage export in the CI environment.
4. Reconcile the DFI/refresh documentation with the current RTL and identify the intended DRAM/PHY target.
5. Audit the reference `axi-on-ucie-to-mem` swarm using Section 8 and approve only reusable infrastructure patterns.
6. Only after those decisions, create the proposed `swarm/` files and agent contracts on isolated branches as described by `doc/SWARM_PLAN.md`.

## 10. Files consulted

- `README.md`
- `doc/SWARM_PLAN.md`
- `doc/DESIGN_SPEC.md`
- `doc/FULL_FUNCTIONALITY_PLAN.md`
- `src/*.v`
- `test/Makefile`, root `Makefile`, `cocotb/Makefile`, `uvm_dv/Makefile`
- `cocotb/*.py`
- `uvm_dv/if/`, `uvm_dv/env/`, `uvm_dv/seq/`, `uvm_dv/tests/`, and `uvm_dv/tb/`
- `formal/`, `verification/formal/`, `syn/`, and `.github/workflows/ci.yml`
