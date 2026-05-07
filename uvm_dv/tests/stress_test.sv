// Stress test — mirrors iverilog Test 14 LFSR stress.
// Separate write and read phases; the DUT gives writes priority so
// interleaving would break AR-order == R-order vs the scoreboard.
class stress_test extends axi4_dfi_base_test;

    `uvm_component_utils(stress_test)

    // Number of seeds to run; increase for deeper regression.
    int unsigned n_seeds = 4;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        timeout_ns = 600_000_000;  // 600 ms — more headroom for stress
    endfunction

    task run_phase(uvm_phase phase);
        stress_seq #(ADDR_W, DATA_W, ID_W) seq;
        phase.raise_objection(this);
        for (int s = 0; s < int'(n_seeds); s++) begin
            seq = stress_seq #(ADDR_W, DATA_W, ID_W)::type_id::create(
                      $sformatf("seq_%0d", s));
            if (!seq.randomize() with { lfsr_seed == int'(s + 1); })
                `uvm_fatal("RAND", "stress_seq randomize failed")
            seq.start(env.get_sequencer());
        end
        phase.drop_objection(this);
    endtask

endclass
