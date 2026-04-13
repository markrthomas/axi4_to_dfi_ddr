# Formal verification (optional)

Heavy checks beyond default **Icarus** simulation. Nothing here is required to run **`make -C test run`**.

## Yosys-only: `async_fifo_gray` bounded safety

This repo includes a **single-clock** wrapper (`fifo_safety_top.sv`) that ties `wr_clk == rd_clk`. That does **not** prove metastability-safe CDC; it proves storage / flag consistency under a synchronous instance of the same RTL (Gray pointers + synchronizers become in-domain delay).

**Script:** `formal/yosys_fifo_safety.ys`  
**Run (from repo root):** `make formal-fifo` or `make -C test formal-fifo`  
**Or:** `cd formal && yosys -q -s yosys_fifo_safety.ys`

Flow: `read_verilog -sv`, `hierarchy -top fifo_safety_top`, `prep`, **`async2sync`** (maps async-reset flops for `sat`), `flatten`, **`sat -seq 45 -prove-asserts -verify`**.

The wrapper:

- Holds an internal **phased reset** so BMC does not start from arbitrary post-`async2sync` register states.
- **Assumes** the host does not push when `full` or pop when `empty`.
- **Asserts** a reference depth counter stays `<= DEPTH` and `full` / `empty` are not both true.

**Note:** Older Yosys (e.g. 0.9) may not parse SV `a -> b` inside `assume`; use `!(a) || b` (as in `fifo_safety_top.sv`).

If **`yosys`** is not installed, **`make formal-fifo`** prints `SKIP` and exits 0 (same pattern as **`syn-check`**).

## SymbiYosys / multi-clock (later)

For true dual-clock BMC or k-induction with `sby`, see historical notes in git history or add a separate `*.sby` when you are ready to install **SymbiYosys** and solvers.

## Top-level `axi4_to_dfi_bridge`

End-to-end properties (AXI + DFI + dual-clock FIFOs) are a later step: start with the FIFO proof above, then add assumptions on masters and PHY models.
