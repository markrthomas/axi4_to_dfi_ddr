// AXI4 agent: sequencer + driver + monitor.
// Set is_active=UVM_PASSIVE to instantiate monitor only (no driver/sequencer).
class axi_agent #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends uvm_agent;

    `uvm_component_param_utils(axi_agent #(ADDR_W, DATA_W, ID_W))

    axi_sequencer #(ADDR_W, DATA_W, ID_W) sequencer;
    axi_driver    #(ADDR_W, DATA_W, ID_W) driver;
    axi_monitor   #(ADDR_W, DATA_W, ID_W) monitor;

    // Forwarded from monitor for env-level subscribers.
    uvm_analysis_port #(axi_seq_item #(ADDR_W, DATA_W, ID_W)) wr_ap;
    uvm_analysis_port #(axi_seq_item #(ADDR_W, DATA_W, ID_W)) rd_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = axi_monitor #(ADDR_W, DATA_W, ID_W)::type_id::create("monitor", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sequencer = axi_sequencer #(ADDR_W, DATA_W, ID_W)::type_id::create("sequencer", this);
            driver    = axi_driver    #(ADDR_W, DATA_W, ID_W)::type_id::create("driver",    this);
        end
        wr_ap = new("wr_ap", this);
        rd_ap = new("rd_ap", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        if (get_is_active() == UVM_ACTIVE)
            driver.seq_item_port.connect(sequencer.seq_item_export);
        monitor.wr_ap.connect(wr_ap);
        monitor.rd_ap.connect(rd_ap);
    endfunction

endclass
