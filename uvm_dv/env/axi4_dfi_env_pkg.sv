// Environment package — compile this before any test package.
package axi4_dfi_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Multiple-implementation analysis imp suffixes used by scoreboard and coverage.
    `uvm_analysis_imp_decl(_wr)
    `uvm_analysis_imp_decl(_rd)

    // Typedefs shared across the env
    `include "axi_seq_item.sv"
    `include "axi_sequencer.sv"
    `include "axi_driver.sv"
    `include "axi_monitor.sv"
    `include "axi_agent.sv"
    `include "dfi_seq_item.sv"
    `include "dfi_monitor.sv"
    `include "dfi_agent.sv"
    `include "axi4_dfi_scoreboard.sv"
    `include "axi4_dfi_coverage.sv"
    `include "axi4_dfi_env.sv"

endpackage : axi4_dfi_env_pkg
