// Sequence package — compile after axi4_dfi_env_pkg.
package axi4_dfi_seq_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4_dfi_env_pkg::*;

    `include "axi4_dfi_base_seq.sv"
    `include "smoke_seq.sv"
    `include "mc_cmd_seq.sv"
    `include "burst_rw_seq.sv"
    `include "fifo_depth_seq.sv"
    `include "slverr_seq.sv"
    `include "stress_seq.sv"

endpackage : axi4_dfi_seq_pkg
