# axi4_to_dfi_ddr

Verilog RTL that connects an **AMBA AXI4** slave interface to **JEDEC DFI**-style signals aimed at a DDR PHY / memory-controller path. The design uses **two clock domains** (AXI vs DFI) with gray-code **async FIFOs** and synchronizers for CDC.

This repository is a practical starting point for simulation and integration; full DRAM scheduling (activate, precharge, refresh, timing, multi-phase DFI) is left to you or to a larger controller stack.

## Repository layout

| Path | Description |
|------|-------------|
| `src/axi4_to_dfi_bridge.v` | Top bridge, `cdc_sync`, `async_fifo_gray`, and AXI4 slave → DFI command/data |
| `src/tb_axi4_to_dfi_bridge.v` | Self-contained testbench, stimulus, and a minimal DFI read model |
| `test/Makefile` | Build and run simulation; optional VCD for **gtkwave** |
| `LICENSE` | MIT |

## Requirements

- [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog`, `vvp`), typically with **Verilog-2001** (`-g2001`)
- Optional: **gtkwave** for viewing waveforms

## Build and test

From the repository root:

```bash
make -C test help     # list Makefile targets
make -C test build    # compile only → test/build/sim.vvp
make -C test run     # build (if needed) and run tests (default: `make -C test`)
make -C test vcd      # run with +vcd → test/build/sim.vcd
make -C test wave     # vcd then launch gtkwave (if in PATH)
make -C test clean    # remove test/build/
```

Manual compile (equivalent to the Makefile sources):

```bash
iverilog -g2001 -Wall -o sim.vvp src/axi4_to_dfi_bridge.v src/tb_axi4_to_dfi_bridge.v
vvp sim.vvp
# optional waveform dump for gtkwave:
vvp sim.vvp +vcd
```

When using `+vcd`, run `vvp` from the `test/` directory so the dump path `build/sim.vcd` matches the Makefile layout, or adjust `$dumpfile` in the testbench for your working directory.

## Interfaces (references)

- **AXI4**: AMBA AXI4 slave signaling (for example ARM *AMBA AXI Protocol*, IHI0022). The RTL is written for interoperability with common AXI4 naming and rules.
- **DFI**: JEDEC **DFI 4.0**-style command and write/read data signals (`dfi_address`, `dfi_bank`, `dfi_ras_n` / `dfi_cas_n` / `dfi_we_n`, `dfi_wrdata*`, `dfi_rddata*`, update/init sidebands, etc.). Newer DFI revisions often keep the same core names on this path.

Exact bus widths are **parameters** on `axi4_to_dfi_bridge` (default 32-bit AXI address, 64-bit data, 18-bit DFI address, and so on).

## Behavior notes

- **Clocks**: `axi_aclk` / `axi_aresetn` for AXI; `dfi_clk` / `dfi_rst_n` for DFI-side sequencing and FIFO write ports. Traffic is gated on `dfi_init_complete` from the PHY side (tie high in a simple test).
- **AXI**: Supported transfers follow the checks encoded in the RTL (for example **INCR**, **single-beat** `AWLEN`/`ARLEN == 0`, full-width `AWSIZE`/`ARSIZE`). Unsupported or illegal combinations are rejected with **AXI SLVERR** on the B/R channels where that logic is implemented; see the sources for the exact conditions.
- **DFI**: Command and data strobes are driven as a **minimal illustrative** sequence toward a PHY model, not a production DRAM command stream.

## License

MIT — see [LICENSE](LICENSE).
