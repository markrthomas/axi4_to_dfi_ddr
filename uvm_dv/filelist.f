// VCS filelist for the AXI4-to-DFI UVM DV environment.
// Compile order matters: RTL → interfaces → env pkg → seq pkg → test pkg → tb_top.

// RTL sources (Verilog-2001, compiled with -v2k compat or -sverilog)
../src/cdc_fifo_lib.v
../src/mc_dfi_scheduler.v
../src/axi4_bridge_frontend.v
../src/dfi_adapter.v
../src/axi4_to_dfi_bridge.v

// Interfaces (SystemVerilog)
if/axi4_if.sv
if/dfi_if.sv

// UVM environment package
env/axi4_dfi_env_pkg.sv

// Sequence package
seq/axi4_dfi_seq_pkg.sv

// Test package
tests/axi4_dfi_test_pkg.sv

// Top-level testbench
tb/tb_top.sv
