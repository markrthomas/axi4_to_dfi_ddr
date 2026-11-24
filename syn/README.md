# syn/ — synthesis, CDC & sign-off collateral (tapeout-readiness)

T1/T2 sign-off flow for `axi4_to_dfi_bridge`, part of the workspace tapeout-readiness
program (`../DESIGN_READINESS.md`).

## Runs here (OSS, no PDK)
```sh
make synth   # Yosys generic synth: latch-free + cell/logic-depth ceilings; emits sim/synth_netlist.v
make cdc     # structural audit: no AXI<->DFI crossing bypasses async_fifo_gray / cdc_sync
```
Both are real artifacts and are gated in CI (the `signoff` job). The design is **two
asynchronous clock domains** (AXI `axi_aclk`, DFI `dfi_clk`) — hence a real CDC gate,
unlike the single-clock sibling blocks.

## Collateral (run where a PDK / STA tool exists)
- `constraints/axi_dfi.sdc` — two async clock groups, async-reset false paths, I/O budgets.
- `sta/opensta.tcl` — OpenSTA (pathfind) / PrimeTime (sign-off) driver; `needs-pdk`.
- `SIGNOFF.md` — the T0–T7 checklist with status and artifact paths.

## Note
This block is still a *bring-up bridge, not a complete DDR controller* — see the
prerequisite banner in `SIGNOFF.md` and `doc/FULL_FUNCTIONALITY_PLAN.md`. These gates
measure controller work as it lands.
