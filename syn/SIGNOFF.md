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
| **T3** low-power | ☐ open | `lp/` (to author) | DFI LP / self-refresh power states. `needs-license` to validate. |
| **T4** DFT | ☐ open | `dft/` (to author) | Scan over scheduler FSM; MBIST if any RAM; ATPG. `needs-license`. |
| **T5** verif sign-off | ◐ partial | directed Icarus + FIFO BMC; UVM (VCS) env named, OSS-UVM hangs | Stand up UVM on a licensed sim; SVA on DRAM command timing; randomized coverage + logged seeds. |
| **T6** GLS + PPA | ☐ open | — | SDF GLS incl. DRAM command timing; power; LEC; PPA. `needs-pdk`. |
| **T7** integration/pkg | ☐ open | `pkg/` (to author) | IP-XACT; register/config map; PHY integration guide (DFI sideband). |

Legend: ✅ passed · ◑ authored-not-run · ◐ partial/pathfind · ☐ not started.
