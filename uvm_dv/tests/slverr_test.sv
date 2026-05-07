// SLVERR test — mirrors iverilog Tests 11, 12, 13.
// Checks SLVERR delivery ordering for both read and write channels.
class slverr_test extends axi4_dfi_base_test;

    `uvm_component_utils(slverr_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        slverr_seq #(ADDR_W, DATA_W, ID_W) seq;
        phase.raise_objection(this);
        seq = slverr_seq #(ADDR_W, DATA_W, ID_W)::type_id::create("seq");
        seq.start(env.get_sequencer());
        phase.drop_objection(this);
    endtask

endclass
