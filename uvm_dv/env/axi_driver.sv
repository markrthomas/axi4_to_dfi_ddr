// AXI4 master driver.
// Drives AW+W (writes) or AR (reads) from sequence items.
// When an AR fires it puts the beat address(es) into phy_addr_mbox so
// the tb_top PHY model can return the correct dfi_rddata later.
class axi_driver #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends uvm_driver #(axi_seq_item #(ADDR_W, DATA_W, ID_W));

    `uvm_component_param_utils(axi_driver #(ADDR_W, DATA_W, ID_W))

    typedef axi_seq_item #(ADDR_W, DATA_W, ID_W) item_t;

    virtual axi4_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)) vif;

    // Shared with tb_top PHY model: driver pushes one address per read beat here.
    mailbox #(logic [ADDR_W-1:0]) phy_addr_mbox;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi4_if #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W)))::get(
                this, "", "axi_vif", vif))
            `uvm_fatal("CFG", "axi_vif not set in config_db")
        if (!uvm_config_db #(mailbox #(logic [ADDR_W-1:0]))::get(
                this, "", "phy_addr_mbox", phy_addr_mbox))
            `uvm_fatal("CFG", "phy_addr_mbox not set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        item_t req;
        drive_idle();
        @(posedge vif.aclk);
        forever begin
            seq_item_port.get_next_item(req);
            if (req.op == AXI_WRITE)
                drive_write(req);
            else
                drive_read(req);
            seq_item_port.item_done();
        end
    endtask

    // De-assert all master-side valids between transactions.
    task drive_idle();
        vif.driver_cb.awvalid <= 1'b0;
        vif.driver_cb.wvalid  <= 1'b0;
        vif.driver_cb.bready  <= 1'b0;
        vif.driver_cb.arvalid <= 1'b0;
        vif.driver_cb.rready  <= 1'b0;
        vif.driver_cb.awid    <= '0;
        vif.driver_cb.awaddr  <= '0;
        vif.driver_cb.awlen   <= 8'd0;
        vif.driver_cb.awsize  <= 3'd3;
        vif.driver_cb.awburst <= 2'b01;
        vif.driver_cb.awlock  <= 1'b0;
        vif.driver_cb.awcache <= 4'b0;
        vif.driver_cb.awprot  <= 3'b0;
        vif.driver_cb.awqos   <= 4'b0;
        vif.driver_cb.awregion<= 4'b0;
        vif.driver_cb.awuser  <= '0;
        vif.driver_cb.arid    <= '0;
        vif.driver_cb.araddr  <= '0;
        vif.driver_cb.arlen   <= 8'd0;
        vif.driver_cb.arsize  <= 3'd3;
        vif.driver_cb.arburst <= 2'b01;
        vif.driver_cb.arlock  <= 1'b0;
        vif.driver_cb.arcache <= 4'b0;
        vif.driver_cb.arprot  <= 3'b0;
        vif.driver_cb.arqos   <= 4'b0;
        vif.driver_cb.arregion<= 4'b0;
        vif.driver_cb.aruser  <= '0;
        vif.driver_cb.wdata   <= '0;
        vif.driver_cb.wstrb   <= '1;
        vif.driver_cb.wlast   <= 1'b0;
        vif.driver_cb.wuser   <= '0;
    endtask

    // Drive one write transaction (AW + W beats + wait-for-B).
    task drive_write(item_t req);
        case (req.wr_order)
            WR_AW_FIRST: begin
                drive_aw(req);
                repeat(2) @(posedge vif.aclk);
                drive_w_beats(req);
            end
            WR_W_FIRST: begin
                drive_w_beats(req);
                repeat(2) @(posedge vif.aclk);
                drive_aw(req);
            end
            default: begin  // WR_SIMUL: present AW and W[0] together
                drive_aw_w_simul(req);
            end
        endcase
    endtask

    // AW phase only (fires handshake then de-asserts).
    task drive_aw(item_t req);
        vif.driver_cb.awid     <= req.id;
        vif.driver_cb.awaddr   <= req.addr;
        vif.driver_cb.awlen    <= req.len;
        vif.driver_cb.awsize   <= req.size;
        vif.driver_cb.awburst  <= req.burst;
        vif.driver_cb.awlock   <= req.lock;
        vif.driver_cb.awcache  <= req.cache;
        vif.driver_cb.awprot   <= req.prot;
        vif.driver_cb.awqos    <= req.qos;
        vif.driver_cb.awregion <= req.region;
        vif.driver_cb.awvalid  <= 1'b1;
        @(posedge vif.aclk);
        while (!vif.driver_cb.awready) @(posedge vif.aclk);
        vif.driver_cb.awvalid <= 1'b0;
    endtask

    // W beats only (drives each beat sequentially).
    task drive_w_beats(item_t req);
        for (int k = 0; k <= int'(req.len); k++) begin
            vif.driver_cb.wdata  <= req.data[k];
            vif.driver_cb.wstrb  <= req.strb[k];
            vif.driver_cb.wlast  <= (k == int'(req.len));
            vif.driver_cb.wvalid <= 1'b1;
            @(posedge vif.aclk);
            while (!vif.driver_cb.wready) @(posedge vif.aclk);
            vif.driver_cb.wvalid <= 1'b0;
        end
        vif.driver_cb.wlast <= 1'b0;
    endtask

    // Simultaneous AW + W[0]; remaining W beats follow immediately.
    task drive_aw_w_simul(item_t req);
        vif.driver_cb.awid     <= req.id;
        vif.driver_cb.awaddr   <= req.addr;
        vif.driver_cb.awlen    <= req.len;
        vif.driver_cb.awsize   <= req.size;
        vif.driver_cb.awburst  <= req.burst;
        vif.driver_cb.awlock   <= req.lock;
        vif.driver_cb.awcache  <= req.cache;
        vif.driver_cb.awprot   <= req.prot;
        vif.driver_cb.awqos    <= req.qos;
        vif.driver_cb.awregion <= req.region;
        vif.driver_cb.awvalid  <= 1'b1;
        vif.driver_cb.wdata    <= req.data[0];
        vif.driver_cb.wstrb    <= req.strb[0];
        vif.driver_cb.wlast    <= (req.len == 8'd0);
        vif.driver_cb.wvalid   <= 1'b1;
        @(posedge vif.aclk);
        // Wait until both AW and W[0] are accepted (may take different cycles).
        while (!(vif.driver_cb.awready && vif.driver_cb.wready))
            @(posedge vif.aclk);
        vif.driver_cb.awvalid <= 1'b0;
        vif.driver_cb.wvalid  <= 1'b0;
        // Remaining W beats (if burst)
        for (int k = 1; k <= int'(req.len); k++) begin
            vif.driver_cb.wdata  <= req.data[k];
            vif.driver_cb.wstrb  <= req.strb[k];
            vif.driver_cb.wlast  <= (k == int'(req.len));
            vif.driver_cb.wvalid <= 1'b1;
            @(posedge vif.aclk);
            while (!vif.driver_cb.wready) @(posedge vif.aclk);
            vif.driver_cb.wvalid <= 1'b0;
        end
        vif.driver_cb.wlast <= 1'b0;
    endtask

    // Drive one read transaction (AR phase; push beat addresses to PHY mailbox).
    task drive_read(item_t req);
        logic [ADDR_W-1:0] beat_a;
        int beat_bytes = (DATA_W / 8);

        vif.driver_cb.arid     <= req.id;
        vif.driver_cb.araddr   <= req.addr;
        vif.driver_cb.arlen    <= req.len;
        vif.driver_cb.arsize   <= req.size;
        vif.driver_cb.arburst  <= req.burst;
        vif.driver_cb.arlock   <= req.lock;
        vif.driver_cb.arcache  <= req.cache;
        vif.driver_cb.arprot   <= req.prot;
        vif.driver_cb.arqos    <= req.qos;
        vif.driver_cb.arregion <= req.region;
        vif.driver_cb.arvalid  <= 1'b1;
        @(posedge vif.aclk);
        while (!vif.driver_cb.arready) @(posedge vif.aclk);

        // AR accepted — push one address per beat so PHY model can return data.
        for (int bi = 0; bi <= int'(req.len); bi++) begin
            beat_a = req.addr + logic'(bi * beat_bytes);
            phy_addr_mbox.put(beat_a);
        end

        // Drop arvalid; defer arlen reset by one time unit to avoid
        // same-timestep race with the DUT's r_legal_outstanding update.
        vif.driver_cb.arvalid <= 1'b0;
        #1;
        vif.driver_cb.arlen   <= 8'd0;
    endtask

endclass
