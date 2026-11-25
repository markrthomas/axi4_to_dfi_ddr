# PPA plan (axi4_to_dfi_ddr)

PPA is part of the T6 sign-off. The full plan — what runs OSS here (the
technology-independent proxy baseline, `make ppa`) and what is deferred as `needs-pdk`
(real area µm², power mW, timing ns via a standard-cell library + OpenROAD/OpenSTA or
PrimeTime/PrimePower) — lives in [`../gls/T6_PLAN.md`](../gls/T6_PLAN.md).

`make ppa` emits, to `syn/ppa/reports/axi4_to_dfi_bridge.ppa.rpt`:
- **area proxy** — generic cell count (≈ 13090) + flip-flop count (≈ 2924), post-synth, flattened;
- **timing proxy** — longest topological logic path (`ltp`), i.e. combinational depth (≈ 402).

These are tracked baselines that move monotonically with the real post-PDK numbers.
