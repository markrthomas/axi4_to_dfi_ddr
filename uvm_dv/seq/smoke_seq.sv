// Smoke sequence — mirrors iverilog Tests 3, 3b, 4, 5, 6, 7.
// Exercises single/burst writes, W-before-AW, AW-before-W, and
// backpressure on both B and R channels.
class smoke_seq #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends axi4_dfi_base_seq #(ADDR_W, DATA_W, ID_W);

    `uvm_object_param_utils(smoke_seq #(ADDR_W, DATA_W, ID_W))

    function new(string name = "smoke_seq");
        super.new(name);
    endfunction

    task body();
        // T3: baseline single write + single read
        send_write_single(32'h0000_1000, 4'h3, 64'hDEADBEEF_00000001);
        send_read_single (32'h0000_1000, 4'h4);

        // T3b: four-beat INCR write burst; read back each beat individually
        send_write_burst(32'h0000_9000, 4'h1, 8'd3, 64'hBEEF9000_00000001);
        send_read_single(32'h0000_9000, 4'h2);
        send_read_single(32'h0000_9008, 4'h3);
        send_read_single(32'h0000_9010, 4'h4);
        send_read_single(32'h0000_9018, 4'h5);

        // T4: AW fires two cycles before W
        send_write_single(32'h0000_2008, 4'h1, 64'hCAFEBABE_12345678, 8'hFF, WR_AW_FIRST);
        send_read_single (32'h0000_2008, 4'h2);

        // T5: W fires two cycles before AW
        send_write_single(32'h0000_3010, 4'h5, 64'h11223344_55667788, 8'hF0, WR_W_FIRST);

        // T6: B-channel backpressure — hold bready low for 4 cycles
        begin
            axi_seq_item #(ADDR_W, DATA_W, ID_W) wr1, wr2;
            wr1 = axi_seq_item #(ADDR_W, DATA_W, ID_W)::type_id::create("wr_bp1");
            start_item(wr1);
            wr1.op = AXI_WRITE; wr1.id = 4'h6;
            wr1.addr = 32'h0000_4000; wr1.len = 0; wr1.size = 3; wr1.burst = 1;
            wr1.data = new[1]; wr1.data[0] = 64'hABCDEF00_00000001;
            wr1.strb = new[1]; wr1.strb[0] = 8'hFF;
            wr1.exp_resp = 0; wr1.bready_delay = 4;
            finish_item(wr1);

            wr2 = axi_seq_item #(ADDR_W, DATA_W, ID_W)::type_id::create("wr_bp2");
            start_item(wr2);
            wr2.op = AXI_WRITE; wr2.id = 4'h7;
            wr2.addr = 32'h0000_4008; wr2.len = 0; wr2.size = 3; wr2.burst = 1;
            wr2.data = new[1]; wr2.data[0] = 64'hABCDEF00_00000002;
            wr2.strb = new[1]; wr2.strb[0] = 8'hFF;
            wr2.exp_resp = 0;
            finish_item(wr2);
        end

        // T7: R-channel backpressure — hold rready low for 4 cycles
        begin
            axi_seq_item #(ADDR_W, DATA_W, ID_W) rd_bp;
            rd_bp = axi_seq_item #(ADDR_W, DATA_W, ID_W)::type_id::create("rd_bp");
            start_item(rd_bp);
            rd_bp.op = AXI_READ; rd_bp.id = 4'h8;
            rd_bp.addr = 32'h0000_5000; rd_bp.len = 0; rd_bp.size = 3; rd_bp.burst = 1;
            rd_bp.exp_resp = 0; rd_bp.rready_delay = 4;
            rd_bp.exp_rdata = new[1];
            rd_bp.exp_rdata[0] = expected_rdata(32'h0000_5000);
            finish_item(rd_bp);
        end
    endtask

endclass
