// Smoke test: baseline write/read, burst write, ordering variants, backpressure.
// Mirrors iverilog Tests 3, 3b, 4, 5, 6, 7.
class smoke_test extends axi4_dfi_base_test;

    `uvm_component_utils(smoke_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        smoke_seq #(ADDR_W, DATA_W, ID_W) seq;
        phase.raise_objection(this);
        seq = smoke_seq #(ADDR_W, DATA_W, ID_W)::type_id::create("seq");
        seq.start(env.get_sequencer());
        phase.drop_objection(this);
    endtask

endclass
