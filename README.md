# axi4_to_dfi_ddr

Verilog RTL that connects an **AMBA AXI4** slave interface to **JEDEC DFI**-style signals aimed at a DDR PHY / memory-controller path. The design uses **two clock domains** (AXI vs DFI) with gray-code **async FIFOs** and synchronizers for CDC.

This repository is a practical starting point for simulation and integration; full DRAM scheduling (activate, precharge, refresh, timing, multi-phase DFI) is left to you or to a larger controller stack.

## Repository layout

| Path | Description |
|------|-------------|
| `src/axi4_to_dfi_bridge.v` | Top bridge, `cdc_sync`, `async_fifo_gray`, and AXI4 slave → DFI command/data |
| `src/tb_axi4_to_dfi_bridge.v` | Self-contained testbench, stimulus, and a minimal DFI read model |
| `Makefile` | Repo root shortcuts: `run`, `clean`, `doc`, `doc-html`, etc. |
| `test/Makefile` | Simulation: **iverilog**/**vvp**, VCD/**gtkwave**; also `doc` / `doc-html` wrappers |
| `doc/DESIGN_SPEC.md` | Design specification (source for PDF/HTML) |
| `doc/Makefile` | `pdf`, `html`, `clean` (outputs under `doc/build/`) |
| `LICENSE` | MIT |

## Requirements

### Simulation

- [Icarus Verilog](http://iverilog.icarus.com/): `iverilog` and `vvp`, usually with **Verilog-2001** (`-g2001`).
- Optional: **gtkwave** to view VCD waveforms.

### Documentation

- **HTML** (`doc/build/design_spec.html`): [pandoc](https://pandoc.org/) only.
- **PDF** (`doc/build/design_spec.pdf`): pandoc plus a LaTeX engine (**pdflatex**). On Debian/Ubuntu-style systems, installing `pandoc` and `texlive-latex-base` (or a fuller TeX Live metapackage) is usually enough.

## Build and test (simulation)

From the **repository root**, you can use the root `Makefile` or call `test/` directly:

```bash
make help             # list root targets
make run              # same as: make -C test run
make build            # compile only → test/build/sim.vvp
make vcd              # run with +vcd → test/build/sim.vcd
make wave             # vcd, then launch gtkwave (if in PATH)
```

Equivalent using `make -C test`:

```bash
make -C test help
make -C test build
make -C test run      # default if you run: make -C test
make -C test vcd
make -C test wave
```

Generated simulation artifacts live under **`test/build/`** (ignored by git).

## Documentation (design spec)

Source: **`doc/DESIGN_SPEC.md`**. Outputs go to **`doc/build/`** (ignored by git).

```bash
# From repo root
make doc              # PDF via pandoc + pdflatex
make doc-html         # standalone HTML via pandoc only

# Or from doc/
make -C doc pdf
make -C doc html
make -C doc help

# Wrappers from test/
make -C test doc
make -C test doc-html
```

Open the PDF with any PDF viewer. Open the HTML in a browser. For PDF builds, if you see LaTeX errors about missing packages, install the suggested TeX Live packages for your OS.

## Clean

Remove **all** generated simulation and documentation outputs (both `test/build/` and `doc/build/`):

```bash
make clean            # from repository root (recommended)
```

To clean only one area:

```bash
make -C test clean    # simulation build only
make -C doc clean     # documentation build only
```

Manual compile (same sources as `test/Makefile`):

```bash
cd test
mkdir -p build
iverilog -g2001 -Wall -o build/sim.vvp ../src/axi4_to_dfi_bridge.v ../src/tb_axi4_to_dfi_bridge.v
vvp build/sim.vvp
vvp build/sim.vvp +vcd   # optional: writes build/sim.vcd (paths match the testbench)
```

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
