# DFT_PLAN.md — axi4_to_dfi_bridge DFT (T4)

DFT intent for the tapeout-readiness program (`../../../DESIGN_READINESS.md`). Adopted from
the sign-off kit's DFT template, tuned to this block.

Two layers (program doctrine — *no artifact = not verified*):

1. **Scan-readiness audit — OSS, runs here now** (`make dft` → `scan_readiness.sh`).
   On the synthesized netlist, asserts the structural conditions that must hold *before*
   scan insertion, and inventories the flops for scan planning. Current result: **PASS**
   (2924 flops, latch-free, no combinational loops; 40% reset-controllable, 1188 async
   set/reset, 0 inferred RAM).
2. **Scan insertion + ATPG — `needs-license`** (DFT Compiler / Tessent scan stitch;
   TestMAX / Tessent ATPG) on the PDK-mapped netlist. Authored here as the recipe.

## Scan-readiness result (this block)

| Metric | Value | Meaning for scan |
|--------|-------|------------------|
| flip-flops | **2924** | scan-chain length budget (balance into N chains) |
| reset-controllable | **40%** | flops with sync/async reset — directly controllable at scan setup |
| async set/reset | **1188** | need async-reset-disable during scan shift (scan-enable gates the reset) |
| D-latches | **0** | HARD PASS — latches are not scannable |
| combinational loops | **0** | HARD PASS — ATPG cannot justify a comb loop |
| memory arrays | **0** | the CDC FIFO / scheduler counters mapped to flops (no RAM macro ⇒ no MBIST here) |

The two async-reset clock domains (`axi_aclk`, `dfi_clk`) mean **two scan regimes**: build
per-domain scan chains, and hold each domain's async reset inactive during its shift (scan
reset gating). The CDC synchronizers across `axi_aclk`↔`dfi_clk` must be bypassed or
lock-up-latch protected on the scan path — see the scan-chain ordering note below.

## Scan insertion + ATPG recipe (needs-license)

1. **Scan stitch** (DFT Compiler / Tessent) on the Liberty-mapped netlist (T6/`needs-pdk`):
   - `set_scan_configuration -style multiplexed_flip_flop`
   - two clock-grouped chains (one per clock domain); do **not** mix `axi_aclk` and
     `dfi_clk` flops in one chain (shift-clock skew across the CDC boundary).
   - lock-up latches at any intra-chain clock-domain handoff.
2. **Scan reset gating**: route `scan_enable` to hold the 1188 async set/reset flops'
   async control inactive during shift.
3. **ATPG** (TestMAX / Tessent): stuck-at + transition; target ≥99% test coverage.
   CDC synchronizer flops → constrain or exclude from at-speed transition patterns.
4. **MBIST**: none required today (no RAM macro). If a FIFO is later remapped to a
   compiled RAM (T6/PPA), add a BIST controller and re-audit.

## Exit criteria (T4)

- Scan-readiness audit PASS (here now).
- Scan chains stitched, DRC-clean (needs-license); ATPG coverage ≥99% stuck-at;
  scan-shift reset gating verified; per-domain chains with lock-up latches confirmed.
