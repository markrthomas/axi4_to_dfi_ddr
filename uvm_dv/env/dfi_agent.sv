// DFI agent — passive only (no driver; PHY model lives in tb_top).
class dfi_agent #(
    parameter int ADDR_W = 18,
    parameter int BANK_W = 3
) extends uvm_agent;

    `uvm_component_param_utils(dfi_agent #(ADDR_W, BANK_W))

    dfi_monitor #(ADDR_W, BANK_W) monitor;

    uvm_analysis_port #(dfi_seq_item #(ADDR_W, BANK_W)) cmd_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = dfi_monitor #(ADDR_W, BANK_W)::type_id::create("monitor", this);
        cmd_ap  = new("cmd_ap", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        monitor.cmd_ap.connect(cmd_ap);
    endfunction

endclass
