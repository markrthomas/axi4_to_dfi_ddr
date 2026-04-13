# axi4_to_dfi_ddr

Verilog RTL that connects an **AMBA AXI4** slave interface to **JEDEC DFI**-style signals aimed at a DDR PHY / memory-controller path. The design uses **two clock domains** (AXI vs DFI) with gray-code **async FIFOs** and synchronizers for CDC.

This repository is a practical starting point for simulation and integration. The RTL includes an **optional** open-page scheduler with **parameterized PRE/ACT/CAS** and an **optional all-bank refresh walk** (`MC_REFRESH_INTERVAL`, default off); full JEDEC scheduling, **tRAS**/**tWR**/**tRFC** class timing, and **multi-phase DFI** are still left to a larger stack or your PHY integration.

## Repository layout

| Path | Description |
|------|-------------|
| `src/axi4_to_dfi_bridge.v` | Top bridge, `cdc_sync`, `async_fifo_gray`, and AXI4 slave → DFI command/data |
| `src/tb_axi4_to_dfi_bridge.v` | Self-contained testbench: dual clocks, PHY read model, **SLVERR** paths, **R/B** backpressure, **rresp**/**bresp** FIFO fill (depth 8), MC command counters, LFSR stress (see **Design spec** section 8) |
| `src/tb_param_smoke.v` | Minimal second top: **`CDC_FIFO_DEPTH=16`**, **`DFI_INIT_START_CYCLES=0`**; one write and one read (**`make -C test run-smoke`**) |
| `src/tb_param_smoke_zcycles.v` | Smoke with **`MC_T_RP`/`MC_T_RCD`/`MC_CL`/`DFI_WRITE_ACK_CYCLES` = 0**; cold write/read + row-miss write/read (**`make -C test run-smoke-zc`**) |
| `src/tb_param_smoke_refresh.v` | Smoke with **`MC_REFRESH_INTERVAL` > 0**: cold write then **PRE** on refresh walk (**`make -C test run-smoke-refresh`**) |
| `src/tb_elab_fail.v` | Four tiny tops used by **`elab-fail-*`** to assert parameter guards print **`ERROR:`** |
| `Makefile` | Repo root shortcuts: `run`, `ci`, `clean`, `doc`, `doc-html`, etc. |
| `test/Makefile` | Simulation: **iverilog**/**vvp**, **`run-smoke`**, **`run-smoke-zc`**, **`run-smoke-refresh`**, **`lint-verilator`**, **`syn-check`**, **`ci`**; VCD/**gtkwave**; `doc` / `doc-html` wrappers |
| `.github/workflows/ci.yml` | **GitHub Actions**: **`make -C test ci`** on **main** |
| `doc/DESIGN_SPEC.md` | Design specification (source for PDF/HTML) |
| `doc/Makefile` | `pdf`, `html`, `clean` (outputs under `doc/build/`) |
| `syn/yosys.ys` | Optional **Yosys** elaboration/synthesis sanity script for the bridge top |
| `syn/constraints.sdc` | Commented **SDC** hints (CDC false paths); not read by Yosys script |
| `formal/README.md` | Pointers for optional SymbiYosys / bounded checks (FIFO first) |
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
make ci               # main TB + smokes + elab-fail + Verilator + optional Yosys syn-check
make audit            # make ci then design PDF (needs pandoc + pdflatex)
make build            # compile only → test/build/sim.vvp
make vcd              # run with +vcd → test/build/sim.vcd
make wave             # vcd, then launch gtkwave (if in PATH)
```

Equivalent using `make -C test`:

```bash
make -C test help
make -C test build
make -C test run      # default if you run: make -C test
make -C test run-smoke   # alternate depth: tb_param_smoke (CDC_FIFO_DEPTH=16)
make -C test run-smoke-zc   # zero-cycle MC timing smoke
make -C test run-smoke-refresh  # MC_REFRESH_INTERVAL refresh PRE
make -C test elab-fail-all  # illegal parameters must fail with ERROR:
make -C test lint-verilator  # optional; skips if verilator not installed
make -C test ci       # run + three smokes + elab-fail-all + lint + syn-check (yosys optional)
make -C test vcd
make -C test wave
```

Continuous integration: **`.github/workflows/ci.yml`** runs **`make -C test ci`** on push and pull request to **`main`** (installs **iverilog** and **verilator** on Ubuntu).

Generated simulation artifacts live under **`test/build/`** (ignored by git).

The default **`make run`** test sequence is summarized in **`doc/DESIGN_SPEC.md`** (section **Verification**): init gating, illegal transactions and read-data timeout (**SLVERR**), **B**/**R** stall stability, filling the **gray async** response FIFOs while **RREADY**/**BREADY** are low, dual outstanding reads with different **ARID**, DFI-side **PRE/ACT/CAS** checks, and a deterministic **LFSR**-paced stress phase (writes then reads; see spec). The bench spaces some **AXI** handshakes slightly for reliable **Icarus** + **CDC** behavior.

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
- **AXI**: Supported transfers follow the checks encoded in the RTL: **INCR** writes with `AWLEN` ≤ `C_MAX_WRITE_AWLEN` (default **3**, i.e. up to four beats), full-width `AWSIZE`; **reads** remain single-beat (`ARLEN == 0`, full-width `ARSIZE`). Unsupported or illegal combinations are rejected with **AXI SLVERR** on the B/R channels where that logic is implemented; see the sources for the exact conditions.
- **DFI / memory controller**: The `dfi_clk` side runs an **open-page SDRAM-style** FSM (per-bank row tracking, PRE/ACT/CAS with `MC_T_RP`, `MC_T_RCD`, `MC_CL`). AXI addresses decode as `{bank,row,col}` in the low bits (`MC_*_BITS` parameters). **Refresh** and full JEDEC timing are not implemented yet.
- **Roadmap (in order)**: (1) memory-controller core (open-page PRE/ACT/CAS, `MC_*`) — done; (2) DFI fidelity — in progress (`dfi_act_n` on ACT, optional `dfi_init_start` pulse via `DFI_INIT_START_CYCLES`; P0–P3 phase buses still out of scope); (3) richer AXI — **INCR write bursts** (parameterized `C_MAX_WRITE_AWLEN`, one **B** per burst) done; read bursts / reordering still out; (4) CDC/clock ratio; (5) verification — **Icarus** CI (`make ci`) + elab guards done; **next**: tighten or remove TB handshake spacing once **`async_fifo_gray`** has a **registered read data path** (or show-ahead) co-designed with `rd_empty` / bridge snapshot timing, then **bounded formal** or a **second simulator** on that FIFO alone; (6) **DRAM refresh** + tighter `t*` timing on the MC FSM; (7) synthesis scripts + constraints (CDC false paths); (8) docs. Local pre-release check: **`make audit`** (`ci` + PDF spec).

## License

MIT — see [LICENSE](LICENSE).
