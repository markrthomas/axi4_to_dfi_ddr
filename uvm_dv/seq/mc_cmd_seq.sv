// MC command-count sequence — mirrors iverilog Tests 8a, 8b, 8c.
// Drives specific bank/row/col patterns and asserts expected DFI
// PRE/ACT/RDCAS/WRCAS counts via the dfi_monitor reference.
//
// The test that uses this sequence must call
//   dfi_mon.reset_counts() before and check counts after.
class mc_cmd_seq #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W);

    `uvm_object_param_utils(mc_cmd_seq #(ADDR_W, DATA_W, ID_W))

    function new(string name = "mc_cmd_seq");
        super.new(name);
    endfunction

    task body();
        // 8a: open-page read hit — row already open in bank 5.
        //     Prime the row with a write first, then read different column.
        //     Expect: 0 PRE, 0 ACT, 1 RDCAS, 0 WRCAS during monitored window.
        send_write_single(mc_addr(3'd5, 14'd24, 10'd0), 4'hE, 64'hCAFEBABE_00000001);
        // (MC opens bank 5 row 24 for the write; row stays open)
        send_read_single (mc_addr(3'd5, 14'd24, 10'd4), 4'hF);

        // 8b: row miss — same bank 4, different row → PRE + ACT + WRCAS.
        //     Prime row 5 first (cold open), then access row 6 (miss).
        //     Expect during second write: 1 PRE, 1 ACT, 0 RDCAS, 1 WRCAS.
        send_write_single(mc_addr(3'd4, 14'd5, 10'd0),  4'h9, 64'hDEAD6000_00006000);
        send_write_single(mc_addr(3'd4, 14'd6, 10'd0),  4'h2, 64'hDEAD6800_00006800);

        // 8c: cold bank 7 (first access ever) — ACT + WRCAS, no PRE.
        //     Expect: 0 PRE, 1 ACT, 0 RDCAS, 1 WRCAS.
        send_write_single(32'h0700_0000, 4'hB, 64'hA5B7C0DE_07000000);
    endtask

endclass
