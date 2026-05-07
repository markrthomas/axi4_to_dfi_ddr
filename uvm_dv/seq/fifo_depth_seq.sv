// FIFO depth stress sequence — mirrors iverilog Tests 9 and 10.
//
// T9: Fill RRESP FIFO (depth 8) by holding rready low while 8 reads complete.
//     Then drain all 8 in order.
// T10: Fill BRESP FIFO (depth 8) by holding bready low while 8 writes complete.
//      Then drain all 8 in order.
//
// Note: the driver's rready_delay / bready_delay fields control backpressure;
// the env drives rready=0 until the delay expires then pulses it per beat.
class fifo_depth_seq #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W);

    `uvm_object_param_utils(fifo_depth_seq #(ADDR_W, DATA_W, ID_W))

    localparam int FIFO_DEPTH = 8;

    function new(string name = "fifo_depth_seq");
        super.new(name);
    endfunction

    task body();
        logic [ADDR_W-1:0] base_r = mc_addr(3'd6, 14'd200, 10'd0);
        logic [ADDR_W-1:0] base_w = mc_addr(3'd2, 14'd88,  10'd0);
        int beat_bytes = DATA_W / 8;

        // --- T9: 8 reads with rready held low (RRESP FIFO stress) ---
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            axi_seq_item #(ADDR_W, DATA_W, ID_W) rd;
            rd = axi_seq_item #(ADDR_W, DATA_W, ID_W)::type_id::create("rd_fifo");
            start_item(rd);
            rd.op          = AXI_READ;
            rd.id          = logic'(i[ID_W-1:0]);
            rd.addr        = base_r + logic'(i * beat_bytes);
            rd.len         = 8'd0;
            rd.size        = 3'd3;
            rd.burst       = 2'b01;
            rd.exp_resp    = 2'b00;
            rd.exp_rdata   = new[1];
            rd.exp_rdata[0] = expected_rdata(rd.addr);
            // First 7 hold rready low for 200 cycles to let the FIFO fill;
            // final item has no extra delay (drain happens after all are queued).
            rd.rready_delay = (i < FIFO_DEPTH-1) ? 200 : 0;
            finish_item(rd);
        end

        // --- T10: 8 writes with bready held low (BRESP FIFO stress) ---
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            axi_seq_item #(ADDR_W, DATA_W, ID_W) wr;
            wr = axi_seq_item #(ADDR_W, DATA_W, ID_W)::type_id::create("wr_fifo");
            start_item(wr);
            wr.op          = AXI_WRITE;
            wr.id          = logic'(i[ID_W-1:0]);
            wr.addr        = base_w + logic'(i * beat_bytes);
            wr.len         = 8'd0;
            wr.size        = 3'd3;
            wr.burst       = 2'b01;
            wr.data        = new[1]; wr.data[0] = 64'hB0DF0000_00000000 + logic'(i);
            wr.strb        = new[1]; wr.strb[0] = 8'hFF;
            wr.exp_resp    = 2'b00;
            wr.bready_delay = (i < FIFO_DEPTH-1) ? 200 : 0;
            finish_item(wr);
        end
    endtask

endclass
