// MC command count test: open-page hit, row miss, cold bank.
// Mirrors iverilog Tests 8a, 8b, 8c.
// Checks DFI PRE/ACT/RDCAS/WRCAS counts for each scenario.
class mc_cmd_test extends axi4_dfi_base_test;

    `uvm_component_utils(mc_cmd_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        mc_cmd_seq  #(ADDR_W, DATA_W, ID_W) seq;
        dfi_monitor #(DFI_ADDR_W, DFI_BANK_W) dfi_mon;

        phase.raise_objection(this);
        dfi_mon = env.get_dfi_monitor();
        seq     = mc_cmd_seq #(ADDR_W, DATA_W, ID_W)::type_id::create("seq");

        // --- 8a: open-page read hit ---
        // Prime bank 5 row 24 via the write in mc_cmd_seq, then read.
        // The priming write happens without monitoring; the read should
        // see only 1 RDCAS (row already open).
        dfi_mon.reset_counts();
        // Run just the first two items (write + read for 8a) by using a
        // targeted sub-sequence rather than the full mc_cmd_seq.
        begin
            axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W) s8a;
            s8a = axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W)::type_id::create("s8a");
            // Prime write (not monitored)
            s8a.send_write_single(s8a.mc_addr(3'd5,14'd24,10'd0), 4'hE,
                                  64'hCAFEBABE_00000001);
            // Reset counts after prime
            dfi_mon.reset_counts();
            // Monitored read (open-page hit)
            s8a.send_read_single(s8a.mc_addr(3'd5,14'd24,10'd4), 4'hF);
            s8a.start(env.get_sequencer());
        end
        #(48 * 14);  // wait 48 dfi_clk cycles (~14 ns each)
        check_counts(dfi_mon, 0, 0, 1, 0, "8a open-page hit");

        // --- 8b: row miss ---
        begin
            axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W) s8b;
            s8b = axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W)::type_id::create("s8b");
            // Prime bank 4 row 5
            s8b.send_write_single(s8b.mc_addr(3'd4,14'd5,10'd0), 4'h9,
                                  64'hDEAD6000_00006000);
            s8b.start(env.get_sequencer());
        end
        dfi_mon.reset_counts();
        begin
            axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W) s8b2;
            s8b2 = axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W)::type_id::create("s8b2");
            // Row miss: different row in same bank
            s8b2.send_write_single(s8b2.mc_addr(3'd4,14'd6,10'd0), 4'h2,
                                   64'hDEAD6800_00006800);
            s8b2.start(env.get_sequencer());
        end
        #(64 * 14);
        check_counts(dfi_mon, 1, 1, 0, 1, "8b row miss");

        // --- 8c: cold bank ---
        dfi_mon.reset_counts();
        begin
            axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W) s8c;
            s8c = axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W)::type_id::create("s8c");
            s8c.send_write_single(32'h0700_0000, 4'hB, 64'hA5B7C0DE_07000000);
            s8c.start(env.get_sequencer());
        end
        #(64 * 14);
        check_counts(dfi_mon, 0, 1, 0, 1, "8c cold bank");

        phase.drop_objection(this);
    endtask

    function void check_counts(
        dfi_monitor #(DFI_ADDR_W, DFI_BANK_W) mon,
        int unsigned exp_pre, int unsigned exp_act,
        int unsigned exp_rdcas, int unsigned exp_wrcas,
        string label
    );
        if (mon.cnt_pre   != exp_pre)
            `uvm_error("MC", $sformatf("%s: PRE   exp %0d got %0d", label, exp_pre,   mon.cnt_pre))
        if (mon.cnt_act   != exp_act)
            `uvm_error("MC", $sformatf("%s: ACT   exp %0d got %0d", label, exp_act,   mon.cnt_act))
        if (mon.cnt_rdcas != exp_rdcas)
            `uvm_error("MC", $sformatf("%s: RDCAS exp %0d got %0d", label, exp_rdcas, mon.cnt_rdcas))
        if (mon.cnt_wrcas != exp_wrcas)
            `uvm_error("MC", $sformatf("%s: WRCAS exp %0d got %0d", label, exp_wrcas, mon.cnt_wrcas))
    endfunction

endclass
