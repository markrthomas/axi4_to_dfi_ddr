// Burst read/write sequence — mirrors iverilog Test 8d.
// Issues a 4-beat INCR read burst (ARLEN=3) to a single SDRAM row and
// verifies all beats via the scoreboard.
class burst_rw_seq #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W);

    `uvm_object_param_utils(burst_rw_seq #(ADDR_W, DATA_W, ID_W))

    // Target bank/row (must be in a single SDRAM row to satisfy ar_in_one_row).
    rand logic [2:0]  bank;
    rand logic [13:0] row;

    constraint row_range_c { row inside {[200:250]}; }

    function new(string name = "burst_rw_seq");
        super.new(name);
    endfunction

    task body();
        logic [ADDR_W-1:0] base;

        if (!this.randomize()) `uvm_fatal("RAND", "burst_rw_seq randomize failed")

        base = mc_addr(bank, row, 10'd0);

        // 4-beat INCR read burst: beats at col 0,8,16,24 (all in same row).
        send_read_burst(base, 4'hE, 8'd3);
    endtask

endclass
