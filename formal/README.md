# Formal verification (optional)

This tree is reserved for **bounded or full formal** runs that are heavier than the default **Icarus** simulation CI. Nothing here is required to build or simulate the bridge.

## Suggested first target: `async_fifo_gray`

The gray-pointer FIFO in `src/axi4_to_dfi_bridge.v` is self-contained enough to **black-box** or **cut** the rest of the design and prove small properties, for example:

- **FIFO depth / power-of-two**: already enforced by `initial` in RTL; formal can treat as assumption.
- **Safety**: `wr_en && !full` does not corrupt `mem`; `rd_en && !empty` does not advance past empty (with correct Gray full/empty).
- **Bounded reset**: both domains in reset, then release write side, then read side (or symmetric), for a bounded cycle limit.

A typical flow is **SymbiYosys** (`sby`) with **Yosys** + **BMC** (e.g. `bmc` mode, 20–200 cycles depending on depth). You will need to:

1. Instantiate or extract `async_fifo_gray` as the top (or use `chformal` / manual bind of assertions).
2. Constrain `wr_en` / `rd_en` as fair or arbitrary inputs under invariants you want to disprove.
3. Add **SystemVerilog assertions** in a bind file or a wrapper module if you prefer not to touch the Verilog-2001 core.

CDC **metastability** is not what BMC on RTL registers proves; keep claims to **digital safety/liveness under ideal synchronizer inputs** unless you use specialized CDC tools.

## Top-level `axi4_to_dfi_bridge`

Full-bridge properties touch **AXI sequencing**, **DFI command timing**, and **two-clock FIFOs** at once. Treat that as a later step: start with the FIFO, then add **assume** on AXI masters and **assume** on the PHY model before attempting end-to-end properties.
