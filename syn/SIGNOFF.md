# SIGNOFF.md — axi4_to_dfi_ddr tapeout sign-off checklist

Tracks the eight T-gates from the workspace program (`../DESIGN_READINESS.md`) for this
block. A gate passes only with a cited **artifact** (*no artifact = not verified*);
`needs-license` / `needs-pdk` items are authored here and run where the tools/PDK exist.

**Design facts pinned by the pathfinder:** two asynchronous clock domains — AXI
(`axi_aclk`/`axi_aresetn`) and DFI/DRAM (`dfi_clk`/`dfi_rst_n`); all crossings go
through `async_fifo_gray` / `cdc_sync` (asserted by `make cdc`). Top:
`axi4_to_dfi_bridge`. Latch-free; 13090 cells, logic depth 46 (Yosys generic map).

> **Prerequisite above all gates:** this block is a *bring-up bridge, not a complete
> DDR controller*. Phases 1–7 of `doc/FULL_FUNCTIONALITY_PLAN.md` (JEDEC timing, DRAM
> init/MRS, ZQ, multi-phase DFI, response-queue) must land before T-gate sign-off is
> meaningful. The gates below are stood up now so controller work is measured against them.

| Gate | Status | Artifact / where | Notes |
|------|--------|------------------|-------|
| **T0** spec freeze | ☐ open | `doc/FULL_FUNCTIONALITY_PLAN.md` | Freeze AXI subset + DDR gen/speed-bin + DFI profile; cite DFI rev + JESD79/209 clauses. |
| **T1** synthesizable | ◐ **PASS** | `make synth` → `sim/synth_netlist.v`, `sim/synth.log` | Latch-free; cells/depth within ceilings. Liberty-mapped synth = `needs-pdk`. |
| **T1-CDC** | ✅ **PASS** | `make cdc` → `sim/cdc.log` | No unsynchronized AXI↔DFI crossing (structural Yosys audit). |
| **T2** STA | ◐ collateral | `syn/constraints/axi_dfi.sdc`, `syn/sta/opensta.tcl` | Two async clock groups, async-reset false paths, I/O budgets. **sky130 open-PDK run:** `make pnr` (LibreLane, CI `silicon.yml`) → `syn/pnr/reports/axi4_to_dfi_bridge.pnr.rpt` — 9-corner STA against this SDC, DRC/LVS/antenna, area/power; FAIL on flow/DRC/LVS/hold, setup reported (multi-clock: worst WNS over both groups, no single Fmax). **P&R result (CI silicon run 46047358990, 2026-11-27): PASS** — 70177 cells, 374k µm² die, 308 mW nominal (default activity), DRC 0, LVS clean, antenna 0, hold met all 9 corners (worst +0.138 ns, max_ss), setup NOT MET against the 400/800 MHz placeholders (worst WNS tt −3.8 ns, ss −8.9 ns), max-slew 695 / max-cap 20 (electrical warnings). Clock targets (400/800 MHz) are placeholders — owner's call. Commercial-node STA = `needs-pdk`. |
| **T3** low-power | ◐ authored + OSS-lint | `make lp` → `syn/lp/axi_dfi.upf`, `syn/lp/LP_PLAN.md` | DDR self-refresh power intent (PD_AON AXI frontend + switchable PD_DFI); UPF consistency lint PASS (2 domains/3 supplies/iso+ret/3 PST). VCS `-upf` + RTL↔UPF LEC = `needs-license`. |
| **T4** DFT | ◐ **PASS** (scan-ready) | `make dft` → `syn/dft/reports/`, `syn/dft/DFT_PLAN.md` | Latch-free + no comb loops; 2924 flops (40% reset-controllable, 1188 async set/reset, 0 RAM). Per-domain scan chains over `axi_aclk`/`dfi_clk`. Scan stitch + ATPG = `needs-license`. |
| **T5** verif sign-off | ◐ partial | directed Icarus + FIFO BMC; UVM (VCS) env named, OSS-UVM hangs | Stand up UVM on a licensed sim; SVA on DRAM command timing; randomized coverage + logged seeds. |
| **T6** GLS + PPA | ◐ **PASS** (zero-delay GLS + PPA proxy) | `make gls` → `syn/gls/reports/axi4_to_dfi_bridge.gls.rpt`; `make ppa` → `syn/ppa/reports/axi4_to_dfi_bridge.ppa.rpt`; `syn/gls/T6_PLAN.md` | **GLS:** the generic-gate netlist **simulates clean** — the directed self-checking `tb_axi4_to_dfi_bridge` (FIFO + SLVERR ordering + timeout + stress + MC) passes against the netlist (Yosys `simcells`/`simlib`), synthesized at the TB's `DFI_INIT_START_CYCLES=4` override (auto-`chparam`), catching synth/sim mismatch + X-prop across `axi_aclk`/`dfi_clk`. **PPA proxy:** cells≈13090, flops≈2924, logic-depth≈402. **Post-route GLS (sky130):** `make gls-sky130` runs the same TB on LibreLane's routed netlist with the sky130_fd_sc_hd models (functional, unit delay) → `syn/pnr/reports/axi4_to_dfi_bridge.gls.rpt`; the netlist is built at `SYNTH_PARAMETERS DFI_INIT_START_CYCLES=4` (the TB's value — `gls.sh` FAILs a TB/netlist param mismatch). **Result: FAIL (open, under diagnosis)** — on the routed netlist the TB printed nothing after its seed line for 3600 s (TIMEOUT); the same TB takes 11 s on the generic netlist. A sim-time heartbeat is now on to tell a stuck sim time from an advancing one. SDF-timing GLS incl. DRAM command timing, RTL↔netlist LEC = open (T6_PLAN.md). Adopted from the kit; pathfound on #3. |
| **T7** integration/pkg | ◐ **PASS** (IP-XACT + guide, gated) | `make pkg` → `pkg/check_ipxact.sh`; `pkg/ip-xact/axi4_to_dfi_bridge.xml`, `pkg/INTEGRATION.md` | IP-XACT (IEEE 1685-2014): AXI4 slave + DFI master + 2 clocks + 2 resets bus interfaces, full 71-port model, `S_AXI_map` DRAM memory map, parameter set. `make pkg` gates well-formed + structural + **IP-XACT↔RTL port-sync** (71/71; fails on drift). Integration guide + CDC/clock/reset + config matrix in `pkg/INTEGRATION.md`. No CSR RAL: memory/clock bridge, so the "register map" is the DRAM address space. **Full XSD:** `make pkg-xsd` (IEEE 1685-2014 from Accellera → eda.org → pinned GitHub copy, SHA-256 pinned) → XSD valid. **Release flow:** `make release-check` (reproducible bundle + `MANIFEST.json`, CI dry run) and `.github/workflows/release.yml`; publishing is **blocked until T0** (pre-flight requires `contract-v1.0` + `doc/design_contract.md`). |

Legend: ✅ passed · ◑ authored-not-run · ◐ partial/pathfind · ☐ not started.
