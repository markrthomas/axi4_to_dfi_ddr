// SLVERR ordering sequence — mirrors iverilog Tests 11, 12, 13.
//
// T11: Illegal INCR read with ARLEN=4 (> C_MAX_READ_ARLEN=3) → SLVERR.
//      Issued when no legal reads are outstanding (r_legal_outstanding=0).
//
// T12: Two legal reads with different ARIDs; verify both complete in issue order.
//
// T13: Same ARID for legal write + illegal write + legal read + illegal read.
//      Verifies that SLVERR responses are delivered AFTER preceding legal
//      responses for the same ID.
class slverr_seq #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W);

    `uvm_object_param_utils(slverr_seq #(ADDR_W, DATA_W, ID_W))

    function new(string name = "slverr_seq");
        super.new(name);
    endfunction

    task body();
        // T11: illegal ARLEN (too long) → immediate SLVERR
        send_read_illegal(mc_addr(3'd3, 14'd50, 10'd0), 4'h4,
                          .arlen(8'd4));   // 4 > C_MAX_READ_ARLEN=3

        // T12: two legal reads — scoreboard checks completion order
        send_read_single(mc_addr(3'd1, 14'd10, 10'd0), 4'hA);
        send_read_single(mc_addr(3'd1, 14'd10, 10'd8), 4'hC);

        // T13: interleaved legal / SLVERR pairs for writes and reads.
        // Write: legal (ID 9) then illegal FIXED (ID 9); expect OKAY then SLVERR.
        send_write_single       (mc_addr(3'd0, 14'd300, 10'd0), 4'h9, 64'h0BADBEEF_00000001);
        send_write_illegal_fixed(mc_addr(3'd0, 14'd300, 10'd8), 4'h9, 64'h0BADBEEF_00000002);

        // Read: legal (ID A) then illegal size (ID A); expect OKAY then SLVERR.
        send_read_single (mc_addr(3'd0, 14'd301, 10'd0), 4'hA);
        send_read_illegal(mc_addr(3'd0, 14'd301, 10'd8), 4'hA,
                          .arlen(8'd0), .arsize(3'd2));  // wrong size → rejected
    endtask

endclass
