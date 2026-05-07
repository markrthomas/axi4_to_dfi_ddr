// Test package — compile after axi4_dfi_seq_pkg.
package axi4_dfi_test_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4_dfi_env_pkg::*;
    import axi4_dfi_seq_pkg::*;

    `include "axi4_dfi_base_test.sv"
    `include "smoke_test.sv"
    `include "mc_cmd_test.sv"
    `include "burst_rw_test.sv"
    `include "fifo_depth_test.sv"
    `include "slverr_test.sv"
    `include "stress_test.sv"

endpackage : axi4_dfi_test_pkg
