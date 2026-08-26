# AXI4-to-DFI DDR bridge

## Build and verification

Run commands from the repository root:

```sh
make run                         # Icarus main directed testbench
make ci                          # main testbench, parameter smokes, elaboration guards, lint, Yosys checks
make regress                     # Verilator lint plus directed simulations
make lint                        # Verilator RTL lint only
make syn-check                   # Yosys hierarchy/synthesis sanity check
make formal-fifo                 # Yosys bounded FIFO safety proof
make coverage                    # Verilator coverage; writes coverage.info when verilator_coverage is available
make cocotb                      # OSS cocotb suite (requires cocotb==1.8.1 and Icarus)
make formal                      # SymbiYosys BMC/cover when sby is installed; otherwise legacy FIFO proof
```

Use the narrowest relevant directed target while iterating:

```sh
make -C test run-smoke           # non-default FIFO depth and init-start configuration
make -C test run-smoke-zc        # zero-cycle MC/PHY timing paths
make -C test run-smoke-refresh   # refresh PRE/REF/tRFC behavior
make -C test run-smoke-tras      # tRAS/tWR row-miss behavior
make -C test run-fifo            # dual-clock async FIFO self-check
make -C test run-fifo-verilator  # same FIFO test under Verilator timing
make -C test elab-fail-width     # one expected-invalid parameter configuration
make -C cocotb TESTCASE=test_single_write_read
make -C uvm_dv run TEST=smoke_test  # requires VCS and UVM 1.2
make -C verification/formal bmc     # requires SymbiYosys
```

The normal simulation uses Icarus with Verilog-2001 (`iverilog -g2001 -Wall`). `make -C test ci` skips Yosys-dependent checks when Yosys is absent, so install the CI tool set (`iverilog`, `verilator`, `yosys`) when validating all gates locally. Build the design spec with `make doc` (PDF) or `make doc-html`.

## Architecture

`axi4_to_dfi_bridge` is the integration top and passes shared width, CDC, and memory-controller parameters to two domains:

- `axi4_bridge_frontend` runs on `axi_aclk`. It pairs independent AW/W handshakes, validates the supported AXI subset, transports write and read requests through `wreq`/`rreq` async FIFOs, and returns `bresp`/`rresp` FIFO data on B/R.
- `dfi_adapter` runs on `dfi_clk`; it ties unsupported DFI update/low-power sidebands low, optionally pulses `dfi_init_start`, and instantiates `mc_dfi_scheduler`.
- `mc_dfi_scheduler` consumes one FIFO request at a time, prioritizing writes over reads. It tracks an open row per bank and emits PRE/ACT/CAS sequences, DFI write data, read-data requests, B responses, and beat-level R responses. Optional refresh blocks FIFO pops, closes open banks, issues REF, and holds for `MC_T_RFC`.
- `cdc_fifo_lib` provides `cdc_sync` and the four gray-pointer async FIFOs. FIFO read data is registered and stable while `rd_empty == 0`; the scheduler must snapshot FIFO output when asserting `*_rd_en` and unpack it on the following cycle.

Address fields are decoded from AXI-address low bits as `{bank, row, col}` with `col = [MC_COL_BITS-1:0]`, followed by `row`, then `bank`. The top deliberately has no AXI-to-DFI data-width conversion.

## Repository-specific conventions

- Preserve RTL compile order: `cdc_fifo_lib.v`, `mc_dfi_scheduler.v`, `axi4_bridge_frontend.v`, `dfi_adapter.v`, then `axi4_to_dfi_bridge.v`. Keep `test/Makefile`, `syn/yosys.ys`, cocotb sources, and `uvm_dv/filelist.f` aligned if RTL files are added or renamed.
- The supported AXI subset is full-width, aligned INCR only. Writes are limited by `C_MAX_WRITE_AWLEN` and must have correctly positioned `WLAST`; reads are limited by `C_MAX_READ_ARLEN` and must remain within one decoded DRAM row. Unsupported shapes return SLVERR rather than being sent to DFI.
- Local decode/drain SLVERR responses are deliberately held until older legal B/R responses drain. Preserve `b_legal_outstanding` and `r_legal_outstanding` accounting when changing acceptance or response behavior.
- `CDC_FIFO_DEPTH` must be a power of two and at least 2; it must also be at least `C_MAX_READ_ARLEN + 1`. Keep all top-level elaboration guards and their matching `tb_elab_fail` targets current when adding constrained parameters.
- DFI work is gated by synchronized `dfi_init_complete`. Requests are serialized; do not assume AXI acceptance order equals response availability across the CDC boundary.
- The scheduler supports zero values for timing parameters and has explicit state handling for them. For `DFI_WRITE_ACK_CYCLES=0`, it still spends one `ST_WAIT_B` cycle to push B. Verify both default and zero-cycle paths after timing-FSM changes.
- `dfi_wrdata_mask` is the inverse of AXI `WSTRB`; preserve that PHY-facing convention unless all models and integration documentation change together.
- The built-in formal proof is a bounded, single-clock FIFO safety check, not dual-clock CDC signoff. Its host assumptions prohibit push-on-full, pop-on-empty, and simultaneous push/pop.

`doc/DESIGN_SPEC.md` is the detailed behavioral reference; `doc/FULL_FUNCTIONALITY_PLAN.md` is the staged backlog for capabilities not yet implemented.
