// Top-level UVM environment for the AXI4-to-DFI bridge.
// Instantiates: AXI agent (active), DFI agent (passive), scoreboard, coverage.
class axi4_dfi_env #(
    parameter int ADDR_W     = 32,
    parameter int DATA_W     = 64,
    parameter int ID_W       = 4,
    parameter int DFI_ADDR_W = 18,
    parameter int DFI_BANK_W = 3
) extends uvm_env;

    `uvm_component_param_utils(axi4_dfi_env #(ADDR_W, DATA_W, ID_W, DFI_ADDR_W, DFI_BANK_W))

    typedef axi_seq_item    #(ADDR_W, DATA_W, ID_W)            axi_item_t;
    typedef dfi_seq_item    #(DFI_ADDR_W, DFI_BANK_W)          dfi_item_t;

    axi_agent         #(ADDR_W, DATA_W, ID_W)                   axi_agnt;
    dfi_agent         #(DFI_ADDR_W, DFI_BANK_W)                 dfi_agnt;
    axi4_dfi_scoreboard #(ADDR_W, DATA_W, ID_W, DFI_ADDR_W)    scoreboard;
    axi4_dfi_coverage   #(ADDR_W, DATA_W, ID_W)                 coverage;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axi_agnt   = axi_agent    #(ADDR_W,DATA_W,ID_W)::type_id::create("axi_agnt",   this);
        dfi_agnt   = dfi_agent    #(DFI_ADDR_W,DFI_BANK_W)::type_id::create("dfi_agnt",this);
        scoreboard = axi4_dfi_scoreboard #(ADDR_W,DATA_W,ID_W,DFI_ADDR_W)::type_id::create("scoreboard",this);
        coverage   = axi4_dfi_coverage   #(ADDR_W,DATA_W,ID_W)::type_id::create("coverage",  this);
    endfunction

    function void connect_phase(uvm_phase phase);
        // Scoreboard receives both write and read completions.
        axi_agnt.wr_ap.connect(scoreboard.wr_imp);
        axi_agnt.rd_ap.connect(scoreboard.rd_imp);
        // Coverage receives write completions (base write) and read completions.
        axi_agnt.wr_ap.connect(coverage.analysis_export);
        axi_agnt.rd_ap.connect(coverage.rd_imp);
    endfunction

    // Convenience accessor so tests can reach the AXI sequencer.
    function axi_sequencer #(ADDR_W,DATA_W,ID_W) get_sequencer();
        return axi_agnt.sequencer;
    endfunction

    // Convenience accessor for the DFI monitor (for MC command count checks).
    function dfi_monitor #(DFI_ADDR_W,DFI_BANK_W) get_dfi_monitor();
        return dfi_agnt.monitor;
    endfunction

endclass
