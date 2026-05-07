// Burst read/write test — mirrors iverilog Test 8d.
// Issues a randomized 4-beat INCR read burst; scoreboard checks all beats.
class burst_rw_test extends axi4_dfi_base_test;

    `uvm_component_utils(burst_rw_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        burst_rw_seq #(ADDR_W, DATA_W, ID_W) seq;
        phase.raise_objection(this);
        seq = burst_rw_seq #(ADDR_W, DATA_W, ID_W)::type_id::create("seq");
        seq.start(env.get_sequencer());
        phase.drop_objection(this);
    endtask

endclass
