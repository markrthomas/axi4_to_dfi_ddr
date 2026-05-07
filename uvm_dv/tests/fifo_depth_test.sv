// FIFO depth test — mirrors iverilog Tests 9 and 10.
// Verifies RRESP and BRESP FIFOs can hold 8 entries while rready/bready are low.
class fifo_depth_test extends axi4_dfi_base_test;

    `uvm_component_utils(fifo_depth_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        fifo_depth_seq #(ADDR_W, DATA_W, ID_W) seq;
        phase.raise_objection(this);
        seq = fifo_depth_seq #(ADDR_W, DATA_W, ID_W)::type_id::create("seq");
        seq.start(env.get_sequencer());
        phase.drop_objection(this);
    endtask

endclass
