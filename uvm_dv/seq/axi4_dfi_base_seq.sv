// Base sequence with helper tasks shared by all sequences.
// All sequences parameterize on (ADDR_W, DATA_W, ID_W) and extend this class.
class axi4_dfi_base_seq #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends uvm_sequence #(axi_seq_item #(ADDR_W, DATA_W, ID_W));

    `uvm_object_param_utils(axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W))

    typedef axi_seq_item #(ADDR_W, DATA_W, ID_W) item_t;

    // Bank/row/column encoding matching the DUT MC address decode:
    //   addr[26:24] = bank (MC_BANK_BITS=3)
    //   addr[23:10] = row  (MC_ROW_BITS=14)
    //   addr[9:0]   = col  (MC_COL_BITS=10)
    localparam int MC_BANK_BITS = 3;
    localparam int MC_ROW_BITS  = 14;
    localparam int MC_COL_BITS  = 10;

    function new(string name = "axi4_dfi_base_seq");
        super.new(name);
    endfunction

    // Pack bank/row/col into an AXI byte address the way the DUT MC decodes it.
    function automatic logic [ADDR_W-1:0] mc_addr(
        logic [MC_BANK_BITS-1:0] bank,
        logic [MC_ROW_BITS-1:0]  row,
        logic [MC_COL_BITS-1:0]  col
    );
        return {{(ADDR_W-MC_BANK_BITS-MC_ROW_BITS-MC_COL_BITS){1'b0}}, bank, row, col};
    endfunction

    // PHY data formula — same as scoreboard expected_rdata.
    function automatic logic [DATA_W-1:0] expected_rdata(logic [ADDR_W-1:0] addr);
        // DFI_ADDR_WIDTH = 18 embedded in upper 18 bits of a 64-bit word.
        return {32'hA5A5A5A5, 14'h0, addr[17:0]};
    endfunction

    // -------------------------------------------------------------------------
    // Helpers that send individual transaction types.
    // -------------------------------------------------------------------------

    // Single-beat write, legal INCR, OKAY expected.
    task send_write_single(
        logic [ADDR_W-1:0]   addr,
        logic [ID_W-1:0]     id,
        logic [DATA_W-1:0]   data,
        logic [DATA_W/8-1:0] strb    = '1,
        wr_order_e           order   = WR_SIMUL
    );
        item_t req;
        req = item_t::type_id::create("wr_single");
        start_item(req);
        req.op       = AXI_WRITE;
        req.id       = id;
        req.addr     = addr;
        req.len      = 8'd0;
        req.size     = 3'd3;
        req.burst    = 2'b01;
        req.data     = new[1]; req.data[0] = data;
        req.strb     = new[1]; req.strb[0] = strb;
        req.exp_resp = 2'b00;
        req.wr_order = order;
        finish_item(req);
    endtask

    // Multi-beat INCR write burst.
    task send_write_burst(
        logic [ADDR_W-1:0]   base_addr,
        logic [ID_W-1:0]     id,
        logic [7:0]          awlen,
        logic [DATA_W-1:0]   first_data = '0,
        logic [DATA_W/8-1:0] strb       = '1,
        wr_order_e           order      = WR_SIMUL
    );
        item_t req;
        req = item_t::type_id::create("wr_burst");
        start_item(req);
        req.op       = AXI_WRITE;
        req.id       = id;
        req.addr     = base_addr;
        req.len      = awlen;
        req.size     = 3'd3;
        req.burst    = 2'b01;
        req.data     = new[int'(awlen)+1];
        req.strb     = new[int'(awlen)+1];
        for (int k = 0; k <= int'(awlen); k++) begin
            req.data[k] = first_data + logic'(k * 8);
            req.strb[k] = strb;
        end
        req.exp_resp = 2'b00;
        req.wr_order = order;
        finish_item(req);
    endtask

    // Illegal FIXED-burst write — DUT should respond SLVERR.
    task send_write_illegal_fixed(
        logic [ADDR_W-1:0]   addr,
        logic [ID_W-1:0]     id,
        logic [DATA_W-1:0]   data
    );
        item_t req;
        req = item_t::type_id::create("wr_illegal");
        start_item(req);
        req.op       = AXI_WRITE;
        req.id       = id;
        req.addr     = addr;
        req.len      = 8'd0;
        req.size     = 3'd3;
        req.burst    = 2'b00;   // FIXED — DUT rejects this with SLVERR
        req.data     = new[1]; req.data[0] = data;
        req.strb     = new[1]; req.strb[0] = '1;
        req.exp_resp = 2'b10;   // SLVERR
        finish_item(req);
    endtask

    // Legal single-beat read.
    task send_read_single(
        logic [ADDR_W-1:0] addr,
        logic [ID_W-1:0]   id
    );
        item_t req;
        req = item_t::type_id::create("rd_single");
        start_item(req);
        req.op         = AXI_READ;
        req.id         = id;
        req.addr       = addr;
        req.len        = 8'd0;
        req.size       = 3'd3;
        req.burst      = 2'b01;
        req.exp_resp   = 2'b00;
        req.exp_rdata  = new[1]; req.exp_rdata[0] = expected_rdata(addr);
        finish_item(req);
    endtask

    // Legal INCR read burst (all beats in one SDRAM row).
    task send_read_burst(
        logic [ADDR_W-1:0] base_addr,
        logic [ID_W-1:0]   id,
        logic [7:0]        arlen
    );
        item_t req;
        int beat_bytes = DATA_W / 8;
        req = item_t::type_id::create("rd_burst");
        start_item(req);
        req.op       = AXI_READ;
        req.id       = id;
        req.addr     = base_addr;
        req.len      = arlen;
        req.size     = 3'd3;
        req.burst    = 2'b01;
        req.exp_resp = 2'b00;
        req.exp_rdata = new[int'(arlen)+1];
        for (int k = 0; k <= int'(arlen); k++)
            req.exp_rdata[k] = expected_rdata(base_addr + logic'(k * beat_bytes));
        finish_item(req);
    endtask

    // Illegal read (e.g. ARLEN > C_MAX_READ_ARLEN=3 or wrong ARSIZE) — SLVERR.
    task send_read_illegal(
        logic [ADDR_W-1:0] addr,
        logic [ID_W-1:0]   id,
        logic [7:0]        arlen  = 8'd4,  // > 3 → rejected
        logic [2:0]        arsize = 3'd3,
        logic [1:0]        arburst = 2'b01
    );
        item_t req;
        req = item_t::type_id::create("rd_illegal");
        start_item(req);
        req.op       = AXI_READ;
        req.id       = id;
        req.addr     = addr;
        req.len      = arlen;
        req.size     = arsize;
        req.burst    = arburst;
        req.exp_resp = 2'b10;   // SLVERR
        finish_item(req);
    endtask

endclass
