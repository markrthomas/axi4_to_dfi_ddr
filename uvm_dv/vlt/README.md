# UVM on open-source Verilator (`uvm_dv/vlt`)

Runs the AXI4->DFI/DDR bridge UVM environment under open-source **Verilator
5.050** with the bundled Accellera UVM 2020.3.1 library — a license-free path
(the repo's `uvm_dv/Makefile` otherwise needs VCS).

## Prerequisites
- **Verilator >= 5.050, UVM-capable** (OSS CAD Suite's is not). Local ref:
  `~/verilator/bin/verilator`. **`unset VERILATOR_ROOT`** after sourcing the OSS
  CAD Suite env. **`UVM_HOME`** = `~/verilator/test_regress/t/uvm`.

## Usage
```sh
V=~/verilator/bin/verilator ; U=~/verilator/test_regress/t/uvm
( unset VERILATOR_ROOT; make -C uvm_dv/vlt lint  VERILATOR=$V UVM_HOME=$U )  # RAM-safe
( unset VERILATOR_ROOT; make -C uvm_dv/vlt smoke VERILATOR=$V UVM_HOME=$U )  # build + run
```
Top `tb_top`; test via `+UVM_TESTNAME` (default `smoke_test`, override with
`UVM_TEST=<name>`; others: mc_cmd_test, burst_rw_test, fifo_depth_test,
slverr_test, stress_test). The `--binary` build belongs in CI
(`.github/workflows/verilator-uvm.yml`), not a RAM-constrained host.

## `uvm_macros.svh`
Required tracked empty include-shim (the monolithic UVM header defines the
macros). Do not delete.
