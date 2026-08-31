# Full Functionality and Verification Plan

**Repository:** axi4_to_dfi_ddr

**Scope:** Roadmap from the current simulation-oriented bridge to a production-grade AXI4-to-DFI/DDR controller integration.

# 1. Current Position

The current RTL is a useful bring-up bridge, not a complete DDR controller. It already includes:

- AXI4 slave handshakes for supported traffic.
- AXI write bursts up to `C_MAX_WRITE_AWLEN`; **INCR** read bursts up to `C_MAX_READ_ARLEN` within one DRAM row (`src/axi4_to_dfi_bridge.v` + `src/mc_dfi_scheduler.v`).
- Four gray-code asynchronous FIFOs across the AXI and DFI clock domains.
- A single-transaction open-page scheduler with PRE/ACT/CAS, basic per-bank row tracking, `MC_T_RP`, `MC_T_RCD`, `MC_T_RAS`, `MC_T_WR`, `MC_CL`, and read-data timeout handling.
- Optional all-bank refresh walk that closes open rows with PRE commands.
- Directed Icarus simulation, parameter smoke tests, elaboration guard tests, Verilator lint, Yosys synthesis sanity, and a bounded Yosys FIFO check.

The main gaps before full functionality are:

- CDC FIFO read data is now registered in the read clock domain; broader formal and second-simulator evidence are still needed.
- Local AXI SLVERR paths are ordered behind older legal same-channel responses by outstanding-response counters, but the implementation supports only one held/pending local error per channel and is not yet a general response-queue architecture.
- The DFI side is single-phase and simplified.
- Refresh now issues a real JEDEC auto-refresh (REF) command with a `MC_T_RFC` hold after precharging open banks; wider JEDEC timing (bank groups, `tRC`/`tRRD`/`tFAW`) is still absent.
- DRAM initialization, mode-register programming, calibration hooks, update handshakes, and low-power flows are not implemented.
- Verification is mostly directed simulation plus a narrow FIFO BMC.

# 2. Engineering Principles

Use the existing design as a prototype and tighten it in small, testable slices:

- Stabilize CDC and AXI ordering before expanding the DRAM controller.
- Split large concerns into modules only when the interface is clear enough to verify independently.
- Treat each newly supported protocol feature as incomplete until it has directed tests, randomized coverage, and at least basic assertions.
- Keep the simplified bridge mode available for fast simulation while adding production-oriented modes behind parameters or new modules.

# 3. Phase 1 - CDC and Response Ordering Hardening

## Goals

- Make request/response crossing deterministic across simulators and synthesis tools.
- Remove remaining nonessential testbench timing spacing now that the FIFO read data is registered.
- Guarantee same-ID AXI response ordering for normal and error responses.

## RTL Updates

- Keep the `async_fifo_gray` read-side contract explicit: **`rd_empty == 0`** means registered **`rd_data`** is stable until **`rd_en`** consumes it.
- Keep `wreq_snapshot`, `rreq_snapshot`, `bresp`, and `rresp` consumers aligned with the registered FIFO contract.
- Replace the initial local-SLVERR pending logic with unified ordered response queues if future AXI features need more than one pending local error per channel.
- Add response queue depth parameters or reuse `CDC_FIFO_DEPTH` where that does not create backpressure coupling.

## Tests

- **Done (baseline hardening):** `tb_async_fifo_gray` drives asynchronous write/read clocks, fills the configured FIFO depth, checks registered-read stability while stalled, and verifies concurrent producer/consumer ordering (`make -C test run-fifo`).
- Add same-ID ordering tests:
  - legal read followed by illegal AR.
  - legal write followed by illegal AW/W.
  - stalled R/B channel while mixed normal and error responses are pending.
- Remove Icarus-only spacing from response drain tests after the new FIFO passes.
- Extend formal FIFO checks to prove:
  - no duplicated words.
  - no lost words.
  - in-order readout.
  - no read when empty and no write when full under host assumptions.

## Exit Criteria

- `make -C test ci` passes with the registered FIFO read path.
- **Done (baseline hardening):** Icarus and Verilator timing both run `tb_async_fifo_gray` cleanly (`make -C test run-fifo` and `make -C test run-fifo-verilator`).
- Formal FIFO proof covers at least the configured CI depth and representative smaller depths.

# 4. Phase 2 - Module Boundaries

## Goals

- Turn the top-level bridge from one monolithic module into verifiable blocks.
- Make AXI, CDC, and memory-controller behavior independently replaceable.

## RTL Updates

- **Progress:** `cdc_fifo_lib.v`, `mc_dfi_scheduler.v`, **`axi4_bridge_frontend.v`** (AXI + FIFOs + ordering), and **`dfi_adapter.v`** (DFI/MC + init pulse) are split from **`axi4_to_dfi_bridge`**; further cleanup can peel a thinner top or add a dedicated **`dfi_adapter`** feature set (P0–P3, real REF).
- Split the design further into:
  - `axi4_slave_frontend`: AW/W/AR decode, burst tracking, illegal transaction handling.
  - `axi_cdc_queues`: request and response CDC FIFOs.
  - `mc_scheduler` (partially satisfied by `mc_dfi_scheduler.v`): internal read/write command scheduling.
  - `dfi_adapter`: DFI command/data/update/init signal presentation.
- Define an internal command/response interface:
  - command type: read/write.
  - ID, address, burst length, beat index, data, strobe.
  - response type: OKAY/SLVERR, ID, data, last.
- Keep the existing top module name as an integration wrapper.

## Tests

- Compile each module with minimal unit benches.
- Add interface-level assertions for valid/ready stability and no dropped commands.
- Keep existing top-level tests as integration regression.

## Exit Criteria

- No behavior regression versus the current test suite.
- New modules can be linted independently.
- Internal interface is documented in `doc/DESIGN_SPEC.md`.

# 5. Phase 3 - AXI Feature Completion

## Goals

- Move from a narrow AXI subset to a practical AXI4 slave implementation.

## RTL Updates

- **Done (baseline):** INCR read bursts with `ARLEN` ≤ `C_MAX_READ_ARLEN`, full-width `ARSIZE`, one-row constraint, per-beat `RLAST`/`RRESP` via `rresp` FIFO; `r_legal_outstanding` matches `1+ARLEN` credits per AR.
- **Remaining read features:**
  - narrow / unaligned transfers and `WSTRB`/`ARSIZE` policies beyond full width.
  - FIXED / WRAP bursts and exclusive access if required.
  - configurable outstanding limits and explicit cross-ID ordering rules.
- Add configurable outstanding transaction limits per channel.
- Support same-ID ordering and define cross-ID ordering behavior explicitly.
- Decide and document support policy for:
  - narrow transfers.
  - unaligned addresses.
  - FIXED and WRAP bursts.
  - exclusive accesses.
  - cache/prot/qos/region/user propagation or tie-off.

## Tests

- Directed AXI burst tests for lengths 1, 2, 4, 8, and maximum configured length.
- Randomized legal traffic with a scoreboard.
- Randomized illegal traffic that verifies SLVERR and ordering.
- Backpressure on every AXI channel.
- Coverage counters for burst length, ID, response type, row hit, row miss, and refresh interaction.

## Exit Criteria

- AXI behavior is fully specified for every AXI input field.
- Unsupported features are rejected predictably.
- Supported bursts pass directed and randomized tests.

# 6. Phase 4 - JEDEC-Style DRAM Scheduling

## Goals

- Replace the illustrative SDRAM-style scheduler with a controller that enforces real DRAM command timing for the selected memory class.

## RTL Updates

- Add a memory profile parameter set for the target device family.
- Implement or explicitly gate:
  - initialization reset/CKE sequencing.
  - mode-register writes.
  - ZQ/calibration hooks where applicable.
  - REF command generation.
  - `tRFC`, `tRC`, `tRRD`, `tFAW`, `tCCD`, `tWTR`, `tRTP`, `tMRD`, and related timing.
  - bank-group timing if the target memory requires it.
- Add configurable page policy:
  - open-page.
  - closed-page.
  - timeout-based precharge.
- Add starvation controls so refresh and reads cannot be indefinitely blocked by writes.

## Tests

- Command monitor assertions for every implemented timing parameter.
- Directed row-hit, row-miss, bank-conflict, and refresh-interrupt tests.
- Randomized traffic with refresh enabled.
- Tests at minimum, typical, and large timing parameter values.

## Exit Criteria

- The command monitor can run independently of the DUT implementation.
- Every timing parameter has a test that would fail if the guard were removed.
- Refresh includes REF and `tRFC`, not only PRE-close behavior. **(baseline done: `ST_RF_CMD` + `MC_T_RFC` hold)**

# 7. Phase 5 - DFI Fidelity

## Goals

- Make the PHY-facing side suitable for a real DFI PHY integration.

## RTL Updates

- Add DFI phase support required by the selected PHY:
  - command/address phase lanes.
  - write-data enable and mask alignment.
  - read-data enable and read-valid alignment.
- Implement controller update, PHY update, low-power, and init handshakes as state machines rather than tie-offs.
- Parameterize write latency, read latency, and DFI clock ratio.
- Document all DFI timing assumptions in the design spec.

## Tests

- DFI bus functional model that checks command/data phase alignment.
- Init/update/low-power handshake tests.
- Clock-ratio sweep tests.
- PHY read-data skew and timeout tests.

## Exit Criteria

- DFI integration assumptions are explicit enough to connect a specific PHY.
- All active DFI sideband handshakes have tests.

# 8. Phase 6 - Verification Infrastructure

## Goals

- Move from directed smoke testing to regression-quality verification.

## Updates

- Add SystemVerilog assertion files for:
  - AXI channel stability.
  - AXI response ordering.
  - FIFO safety.
  - internal command interface stability.
  - DRAM timing legality.
  - DFI phase and handshake rules.
- Add randomized test generation with reproducible seeds.
- Add a scoreboard model that tracks writes and predicts read data.
- Add CI matrix entries for:
  - Icarus directed tests.
  - Verilator lint.
  - Yosys synthesis sanity.
  - formal FIFO checks.
  - at least one second simulator for selected tests, when available.
- Add coverage reporting if the chosen simulator supports it.

## Exit Criteria

- CI has fast smoke tests and a longer regression target.
- A failed timing rule produces a clear assertion failure.
- Random tests print seed values and can be replayed.

# 9. Phase 7 - Synthesis and Integration Readiness

## Goals

- Prepare the RTL for FPGA/ASIC integration rather than only simulation.

## Updates

- Replace generic memory inference where the target flow needs explicit RAM style or wrappers.
- Add CDC constraints for synchronizer paths and FIFO pointer crossings.
- Add timing constraints for AXI and DFI clocks.
- Add reset-domain crossing review for `axi_aresetn`, `dfi_rst_n`, and PHY status inputs.
- Add synthesis reports to CI or documented release checks.
- Add an integration checklist:
  - target memory parameters.
  - PHY DFI version and phase mode.
  - clock ratio.
  - reset sequencing.
  - timing constraints.
  - expected AXI subset.

## Exit Criteria

- The design has a documented synthesis flow.
- CDC paths are constrained and reviewed.
- Integration requirements are captured before tapeout/bitstream use.

# 10. Recommended Near-Term Backlog

Implement these first, in order:

1. **Done (bounded model):** `make formal-fifo-dual-clock` adds a separate depth-4 SymbiYosys model with independent clocks/reset release, a shadow queue, and bounded no-loss/no-duplication/in-order checks. The legacy single-clock harnesses remain intact. This is not CDC signoff: its legal-host, clock-progress, reset, depth, and bounded-traffic limitations are documented in `formal/README.md`.
2. Replace the initial local-SLVERR pending logic with unified ordered response queues if future AXI features need more than one pending local error per channel.
3. Add a second simulator target for FIFO and bridge smoke coverage.
4. Continue modularization: dedicated AXI front-end and optional `dfi_adapter` (CDC + `mc_dfi_scheduler` are already separate files).
5. Burst read scoreboarding and randomized read-burst stress beyond the current directed tests.
6. **Done (baseline):** refresh now precharges open banks then issues a real auto-refresh (REF) command and holds `MC_T_RFC` before resuming (`ST_RF_CMD`/`ST_WAIT_RFC` in `mc_dfi_scheduler.v`, covered by `tb_param_smoke_refresh`). Remaining: per-bank/postponed refresh policy and `tREFI`/`tRFC` values tied to a real memory profile.
7. Add a DFI BFM and phase-alignment checks for the intended PHY.

# 11. Release Gates

Do not call the design full-functionality complete until all of these are true:

- AXI support matrix is complete and documented.
- Every supported AXI transaction shape has directed and randomized tests.
- Same-ID response ordering is tested for normal and error responses.
- CDC FIFO behavior is proven or constrained strongly enough for the target implementation.
- DRAM command timing has assertion coverage.
- Refresh uses real REF timing for the selected memory.
- DFI timing and sideband behavior match the target PHY integration guide.
- `make -C test ci` passes, plus the longer regression target passes with logged seeds.
