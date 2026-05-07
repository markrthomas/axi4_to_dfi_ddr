class axi_sequencer #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends uvm_sequencer #(axi_seq_item #(ADDR_W, DATA_W, ID_W));

    `uvm_component_param_utils(axi_sequencer #(ADDR_W, DATA_W, ID_W))

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass
