# T6 — GLS + PPA plan (axi4_to_dfi_ddr)

T6 is the post-synthesis sign-off: prove the **gate netlist** (not just the RTL) is
functionally correct and characterise its **PPA**. Adopted from the shared sign-off kit
(`dv-swarm-kit/templates/signoff`), which was pathfound on `IP-axi-to-2apbs`.

## What runs here (OSS, no PDK) — real artifacts

| Step | Command | Artifact | Proves |
|------|---------|----------|--------|
| **Zero-delay GLS** | `make gls` (`syn/gls/gls.sh`) | `syn/gls/reports/axi4_to_dfi_bridge.gls.rpt` | The synthesized generic-gate netlist **simulates correctly**: the directed self-checking `src/tb_axi4_to_dfi_bridge.v` (FIFO + SLVERR ordering + timeout + stress + MC checks) passes when driven against the netlist (Yosys `simcells`/`simlib` models), not the RTL. Catches synth/sim mismatch + X-prop across the AXI↔DFI clock domains. |
| **PPA proxy** | `make ppa` (`syn/ppa/ppa.sh`) | `syn/ppa/reports/axi4_to_dfi_bridge.ppa.rpt` | Technology-independent baseline: generic cells ≈ 13090, flip-flops ≈ 2924, logic depth (`ltp`) ≈ 402. Tracked across revisions. |

GLS mechanics: the TB instantiates the DUT with `.DFI_INIT_START_CYCLES(4)` — a
**behavioural** override (RTL default 0). `gls.sh` auto-extracts the TB's integer param
overrides and synthesizes the netlist at them (`chparam -set DFI_INIT_START_CYCLES 4`), so
the gate is built for the config the TB exercises (a netlist folded at the default would
fail the init-cycle check). Netlists/sim binaries land in `syn/gls/build/` (gitignored);
the `.rpt` is the tracked artifact.

## What is deferred — `needs-pdk`

Real T6 sign-off needs a standard-cell library + P&R flow (open: sky130 + OpenROAD/OpenSTA;
or a foundry PDK + PrimeTime/PrimePower/Fusion Compiler):
1. **Liberty-mapped synthesis** — a real standard-cell netlist (vs the generic netlist here).
2. **SDF-annotated (timing) GLS** — re-run the TB on the mapped netlist with `$sdf_annotate`
   back-annotation; setup/hold + glitch behaviour across `axi_aclk`/`dfi_clk` the zero-delay
   GLS cannot see.
3. **STA sign-off** — OpenSTA/PrimeTime with Liberty + `syn/constraints/axi_dfi.sdc` (T2):
   both clocks closed at PVT, CDC paths covered by the T1-CDC audit (`make cdc`).
4. **Area + power** — post-P&R µm²/mW from OpenROAD/PrimePower with GLS switching activity.
5. **RTL↔netlist LEC** — Conformal/Formality (OSS `yosys equiv` does not close on the
   generic netlist; LEC sign-off is a licensed-tool step).
