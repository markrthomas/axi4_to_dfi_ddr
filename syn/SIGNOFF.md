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
| **T2** STA | ◐ collateral | `syn/constraints/axi_dfi.sdc`, `syn/sta/opensta.tcl` | Two async clock groups, async-reset false paths, I/O budgets. Run = `needs-pdk`. |
| **T3** low-power | ◐ authored + OSS-lint | `make lp` → `syn/lp/axi_dfi.upf`, `syn/lp/LP_PLAN.md` | DDR self-refresh power intent (PD_AON AXI frontend + switchable PD_DFI); UPF consistency lint PASS (2 domains/3 supplies/iso+ret/3 PST). VCS `-upf` + RTL↔UPF LEC = `needs-license`. |
| **T4** DFT | ◐ **PASS** (scan-ready) | `make dft` → `syn/dft/reports/`, `syn/dft/DFT_PLAN.md` | Latch-free + no comb loops; 2924 flops (40% reset-controllable, 1188 async set/reset, 0 RAM). Per-domain scan chains over `axi_aclk`/`dfi_clk`. Scan stitch + ATPG = `needs-license`. |
| **T5** verif sign-off | ◐ partial | directed Icarus + FIFO BMC; UVM (VCS) env named, OSS-UVM hangs | Stand up UVM on a licensed sim; SVA on DRAM command timing; randomized coverage + logged seeds. |
| **T6** GLS + PPA | ◐ **PASS** (zero-delay GLS + PPA proxy) | `make gls` → `syn/gls/reports/axi4_to_dfi_bridge.gls.rpt`; `make ppa` → `syn/ppa/reports/axi4_to_dfi_bridge.ppa.rpt`; `syn/gls/T6_PLAN.md` | **GLS:** the generic-gate netlist **simulates clean** — the directed self-checking `tb_axi4_to_dfi_bridge` (FIFO + SLVERR ordering + timeout + stress + MC) passes against the netlist (Yosys `simcells`/`simlib`), synthesized at the TB's `DFI_INIT_START_CYCLES=4` override (auto-`chparam`), catching synth/sim mismatch + X-prop across `axi_aclk`/`dfi_clk`. **PPA proxy:** cells≈13090, flops≈2924, logic-depth≈402. SDF-timing GLS incl. DRAM command timing, Liberty map, real area/power/STA, RTL↔netlist LEC = `needs-pdk` (T6_PLAN.md). Adopted from the kit; pathfound on #3. |
| **T7** integration/pkg | ◐ **PASS** (IP-XACT + guide, gated) | `make pkg` → `pkg/check_ipxact.sh`; `pkg/ip-xact/axi4_to_dfi_bridge.xml`, `pkg/INTEGRATION.md` | IP-XACT (IEEE 1685-2014): AXI4 slave + DFI master + 2 clocks + 2 resets bus interfaces, full 71-port model, `S_AXI_map` DRAM memory map, parameter set. `make pkg` gates well-formed + structural + **IP-XACT↔RTL port-sync** (71/71; fails on drift). Integration guide + CDC/clock/reset + config matrix in `pkg/INTEGRATION.md`. No CSR RAL: memory/clock bridge, so the "register map" is the DRAM address space. Full XSD = `IPXACT_XSD=… make pkg`. |

Legend: ✅ passed · ◑ authored-not-run · ◐ partial/pathfind · ☐ not started.
