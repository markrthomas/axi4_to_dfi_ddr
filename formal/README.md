# Formal verification (optional)

Heavy checks beyond default **Icarus** simulation. Nothing here is required to run **`make -C test run`**.

## Yosys-only: `async_fifo_gray` bounded safety

This repo includes a **single-clock** wrapper (`fifo_safety_top.sv`) that ties `wr_clk == rd_clk`. That does **not** prove metastability-safe CDC; it proves storage / flag consistency under a synchronous instance of the same RTL (Gray pointers + synchronizers become in-domain delay).

**Script:** `formal/yosys_fifo_safety.ys`  
**Run (from repo root):** `make formal-fifo` or `make -C test formal-fifo`  
**Or:** `cd formal && yosys -q -s yosys_fifo_safety.ys`

Flow: `read_verilog -sv`, `hierarchy -top fifo_safety_top`, `prep`, **`async2sync`** (maps async-reset flops for `sat`), `flatten`, **`sat -seq 20 -prove-asserts -set-assumes -verify`**.

The wrapper:

- Holds an internal **phased reset** so BMC does not start from arbitrary post-`async2sync` register states.
- **Assumes** the host does not push when `full` or pop when `empty`, and **at most one of `wr_en` / `rd_en` per cycle** (the RTL allows same-edge wr+rd; this is a deliberate **underapproximation** so bounded BMC stays tractable).
- **Asserts** a shadow FIFO stays within `DEPTH`, `full` / `empty` are not both true, and every accepted read returns the oldest accepted write.

The shadow FIFO advances only on accepted host operations. The DUT’s **`cdc_sync`** on Gray pointers plus the **registered read prefetch** (`rd_data_q` / `rd_valid_q`) means visible `rd_data` lags `wr_en` by several `clk` edges even when `wr_clk == rd_clk`; the assertion therefore compares data only when an accepted `rd_en` consumes the registered head word.

**Note:** Older Yosys (e.g. 0.9) may not parse SV `a -> b` inside `assume`; use `!(a) || b` (as in `fifo_safety_top.sv`).

If **`yosys`** is not installed, **`make formal-fifo`** prints `SKIP` and exits 0 (same pattern as **`syn-check`**).

## SymbiYosys: true dual-clock bounded integrity

**Run (from repo root):** `make formal-fifo-dual-clock`

**Or:** `make -C verification/formal dual-clock`
**Direct:** `cd verification/formal && sby -f async_fifo_dual_clock.sby`

`dual_clock_fifo_safety_top.sv` is separate from the legacy single-clock
wrappers.  It instantiates a depth-4 FIFO and uses SymbiYosys
`multiclock on` with independent symbolic `wr_clk` and `rd_clk`.  A formal
global scheduler permits distinct clock phase/rate interleavings (never a
shared `wr_clk == rd_clk` edge), requires each clock to rise within five
scheduler steps, and allows the two resets to release independently before
both remain high.  Host traffic is held until both local domains have
settled after reset.

The bounded proof (40 scheduler steps, Boolector) maintains a four-entry
shadow queue.  It asserts that every accepted read returns its oldest
accepted write (no reordering/duplication), rejects shadow overflow or
underflow, and bounds how long a nonempty queue head can remain undelivered
(no loss under the progress assumptions). It also asserts that a valid
registered head remains unchanged across an unconsumed read-clock edge. The
read host is intentionally eager: on each read-clock edge it requests exactly
when the registered FIFO output was valid.  Writers and readers must sample
and obey `wr_full` and `rd_empty` at their respective local edges.

### Residual limitations

- This is a bounded depth-4 model, not an unbounded proof for every FIFO
  parameter or arbitrarily long traffic sequence.
- Clock progress, no simultaneous clock edges, monotonic reset release, and
  an eager reader are explicit host/environment assumptions; arbitrary host
  stalls and reset while data is in flight are outside this proof.
- Digital formal does not model metastability, analog recovery/removal,
  synchronizer MTBF, placement, timing constraints, or physical CDC signoff.
- The RTL's registered-read behavior is unchanged: `rd_data` is stable while
  `rd_empty == 0` until a read-clock `rd_en` consumes it.  The new harness
  samples that pre-consumption registered head via the formal scheduler.

## Top-level `axi4_to_dfi_bridge`

End-to-end properties (AXI + DFI + dual-clock FIFOs) are a later step: start with the FIFO proof above, then add assumptions on masters and PHY models.
