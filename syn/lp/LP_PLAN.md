# LP_PLAN.md — axi4_to_dfi_bridge low-power (T3)

Low-power intent for the tapeout-readiness program (`../../../DESIGN_READINESS.md`). Adopted
from the sign-off kit's low-power template, tuned to this block's DDR self-refresh story.

Two layers (program doctrine — *no artifact = not verified*):

1. **UPF consistency lint — OSS, runs here now** (`make lp` → `upf_lint.tcl axi_dfi.upf`).
   No OSS tool models UPF power *semantics*; this catches a malformed/inconsistent UPF
   (dangling domains, supplies, iso/retention strategies, power-state tables) before the
   licensed flow. Current result: **PASS** (2 domains, 3 supplies, iso + retention, 3 PST
   states).
2. **Power-aware simulation + LEC — `needs-license`** (VCS `-upf`; Conformal/Formality
   RTL↔UPF LEC). Authored here as the recipe.

## Power architecture

| Domain | Rail | Contents | Rationale |
|--------|------|----------|-----------|
| **PD_AON** | `VDD` (always-on) | AXI4 slave frontend (`u_axi_fe`, `axi_aclk`) | must stay up so a new host request can trigger self-refresh exit |
| **PD_DFI** | `VDD_SW` (switched) | DFI adapter + DDR command scheduler (`u_dfi`, `dfi_clk`) | power-gated during DRAM self-refresh — the DRAM retains contents autonomously |

- **Header switch** `dfi_hdr_sw`: `VDD → VDD_SW`, gated by `pmu_dfi_pwr_en`.
- **Isolation** `dfi_iso`: clamp PD_DFI outputs crossing into PD_AON to 0 when off
  (`pmu_dfi_iso_en`, active-high, parent location) — the AXI frontend never samples a
  floating DFI-side handshake.
- **Retention** `dfi_ret`: save/restore the scheduler's bank-timing / open-row / config
  state (`pmu_dfi_save`/`pmu_dfi_restore`) so the command engine resumes without re-training.

## Power states

| Mode | VDD | VDD_SW | Meaning |
|------|-----|--------|---------|
| **P0 active**  | ON | ON  | normal AXI↔DDR traffic |
| **P1 drain**   | ON | ON  | PD_DFI isolated, still powered — scheduler drains in-flight commands and issues self-refresh entry (SRE) to the DRAM |
| **P2 selfref** | ON | OFF | PD_DFI rail off, scheduler state retained; DRAM self-refreshes |

Sign-off sequence to run: **P0 → P1 → P2 → P1 → P0**, asserting (a) the scheduler reaches
a quiescent/drained state and the DRAM is in self-refresh before `pmu_dfi_pwr_en` deasserts,
(b) retention save before off / restore after on, (c) no AON corruption while PD_DFI is down,
(d) correct self-refresh *exit* and functional resume on the next AXI request.

## Control (PMU) contract

The power controller (PMU — in PD_AON) drives, in order, for power-down:
`pmu_dfi_save` ↑ → `pmu_dfi_iso_en` ↑ → `pmu_dfi_pwr_en` ↓; and reverse for power-up:
`pmu_dfi_pwr_en` ↑ → (settle + self-refresh exit) → `pmu_dfi_restore` ↑ → `pmu_dfi_iso_en` ↓.
These are the UPF control ports above. A gate-level PMU + the P0→P2→P0 testbench are the next
authored artifact; the `ucie_rdi_to_pcie6_pipe7` repo has a runnable Verilator `-upf`
skeleton (`make verilator_upf`) this block can adopt.

## Exit criteria (T3)

- UPF consistency lint PASS (here now).
- VCS `-upf` power-aware sim of the P0→P2→P0 self-refresh sequence clean; RTL↔UPF LEC clean;
  isolation/retention timing vs. the PMU sequence verified (needs-license).
- `-elements` instance paths in `axi_dfi.upf` confirmed against the synthesized hierarchy.
