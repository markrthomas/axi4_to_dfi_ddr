// UVM top-level testbench for the AXI4-to-DFI bridge.
//
// Responsibilities:
//   - Generate axi_aclk (50 MHz) and dfi_clk (~71.4 MHz).
//   - Drive resets.
//   - Instantiate DUT (axi4_to_dfi_bridge).
//   - Instantiate and connect axi4_if and dfi_if.
//   - Run the DFI PHY read-return model (same logic as the Icarus tb).
//   - Provide the phy_addr_mbox (via config_db) for the AXI driver.
//   - Kick off the UVM run.
`timescale 1ns / 1ps

module tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4_dfi_env_pkg::*;
    import axi4_dfi_seq_pkg::*;
    import axi4_dfi_test_pkg::*;

    // -------------------------------------------------------------------------
    // DUT parameters (must match the DUT instantiation below)
    // -------------------------------------------------------------------------
    localparam int C_AXI_ADDR_WIDTH = 32;
    localparam int C_AXI_DATA_WIDTH = 64;
    localparam int C_AXI_ID_WIDTH   = 4;
    localparam int USER_W           = 1;
    localparam int DFI_ADDR_WIDTH   = 18;
    localparam int DFI_BANK_WIDTH   = 3;
    localparam int DFI_DATA_WIDTH   = 64;
    localparam int DFI_MASK_WIDTH   = DFI_DATA_WIDTH / 8;
    localparam int MC_CL            = 6;   // read CAS latency (cycles after rddata_en)
    localparam int TB_READ_Q_DEPTH  = 64;

    // -------------------------------------------------------------------------
    // Clocks and resets
    // -------------------------------------------------------------------------
    logic axi_aclk   = 1'b0;
    logic dfi_clk    = 1'b0;
    logic axi_aresetn;
    logic dfi_rst_n;

    always #10 axi_aclk = ~axi_aclk;  // 50 MHz
    always #7  dfi_clk  = ~dfi_clk;   // ~71.4 MHz

    initial begin
        axi_aresetn = 1'b0;
        dfi_rst_n   = 1'b0;
        repeat (8) @(posedge axi_aclk);
        axi_aresetn = 1'b1;
        dfi_rst_n   = 1'b1;
    end

    // -------------------------------------------------------------------------
    // Interfaces
    // -------------------------------------------------------------------------
    axi4_if #(
        .ADDR_W(C_AXI_ADDR_WIDTH),
        .DATA_W(C_AXI_DATA_WIDTH),
        .ID_W  (C_AXI_ID_WIDTH),
        .USER_W(USER_W)
    ) axi_if (.aclk(axi_aclk), .aresetn(axi_aresetn));

    dfi_if #(
        .ADDR_W(DFI_ADDR_WIDTH),
        .BANK_W(DFI_BANK_WIDTH),
        .DATA_W(DFI_DATA_WIDTH),
        .MASK_W(DFI_MASK_WIDTH)
    ) dfi (.clk(dfi_clk), .rst_n(dfi_rst_n));

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    axi4_to_dfi_bridge #(
        .DFI_INIT_START_CYCLES(4)
    ) dut (
        .axi_aclk         (axi_aclk),
        .axi_aresetn      (axi_aresetn),
        // AW
        .s_axi_awid       (axi_if.awid),
        .s_axi_awaddr     (axi_if.awaddr),
        .s_axi_awlen      (axi_if.awlen),
        .s_axi_awsize     (axi_if.awsize),
        .s_axi_awburst    (axi_if.awburst),
        .s_axi_awlock     (axi_if.awlock),
        .s_axi_awcache    (axi_if.awcache),
        .s_axi_awprot     (axi_if.awprot),
        .s_axi_awqos      (axi_if.awqos),
        .s_axi_awregion   (axi_if.awregion),
        .s_axi_awuser     (axi_if.awuser),
        .s_axi_awvalid    (axi_if.awvalid),
        .s_axi_awready    (axi_if.awready),
        // W
        .s_axi_wdata      (axi_if.wdata),
        .s_axi_wstrb      (axi_if.wstrb),
        .s_axi_wlast      (axi_if.wlast),
        .s_axi_wuser      (axi_if.wuser),
        .s_axi_wvalid     (axi_if.wvalid),
        .s_axi_wready     (axi_if.wready),
        // B
        .s_axi_bid        (axi_if.bid),
        .s_axi_bresp      (axi_if.bresp),
        .s_axi_buser      (axi_if.buser),
        .s_axi_bvalid     (axi_if.bvalid),
        .s_axi_bready     (axi_if.bready),
        // AR
        .s_axi_arid       (axi_if.arid),
        .s_axi_araddr     (axi_if.araddr),
        .s_axi_arlen      (axi_if.arlen),
        .s_axi_arsize     (axi_if.arsize),
        .s_axi_arburst    (axi_if.arburst),
        .s_axi_arlock     (axi_if.arlock),
        .s_axi_arcache    (axi_if.arcache),
        .s_axi_arprot     (axi_if.arprot),
        .s_axi_arqos      (axi_if.arqos),
        .s_axi_arregion   (axi_if.arregion),
        .s_axi_aruser     (axi_if.aruser),
        .s_axi_arvalid    (axi_if.arvalid),
        .s_axi_arready    (axi_if.arready),
        // R
        .s_axi_rid        (axi_if.rid),
        .s_axi_rdata      (axi_if.rdata),
        .s_axi_rresp      (axi_if.rresp),
        .s_axi_rlast      (axi_if.rlast),
        .s_axi_ruser      (axi_if.ruser),
        .s_axi_rvalid     (axi_if.rvalid),
        .s_axi_rready     (axi_if.rready),
        // DFI
        .dfi_clk          (dfi_clk),
        .dfi_rst_n        (dfi_rst_n),
        .dfi_ctrlupd_req  (dfi.ctrlupd_req),
        .dfi_ctrlupd_ack  (dfi.ctrlupd_ack),
        .dfi_phyupd_req   (dfi.phyupd_req),
        .dfi_phyupd_ack   (dfi.phyupd_ack),
        .dfi_lp_ctrl_req  (dfi.lp_ctrl_req),
        .dfi_lp_ctrl_ack  (dfi.lp_ctrl_ack),
        .dfi_init_start   (dfi.init_start),
        .dfi_init_complete(dfi.init_complete),
        .dfi_address      (dfi.address),
        .dfi_bank         (dfi.bank),
        .dfi_ras_n        (dfi.ras_n),
        .dfi_cas_n        (dfi.cas_n),
        .dfi_we_n         (dfi.we_n),
        .dfi_cs_n         (dfi.cs_n),
        .dfi_odt          (dfi.odt),
        .dfi_cke          (dfi.cke),
        .dfi_act_n        (dfi.act_n),
        .dfi_wrdata       (dfi.wrdata),
        .dfi_wrdata_mask  (dfi.wrdata_mask),
        .dfi_wrdata_en    (dfi.wrdata_en),
        .dfi_rddata       (dfi.rddata),
        .dfi_rddata_valid (dfi.rddata_valid),
        .dfi_rddata_en    (dfi.rddata_en)
    );

    // -------------------------------------------------------------------------
    // Tie unused DFI sideband inputs
    // -------------------------------------------------------------------------
    assign dfi.ctrlupd_ack = 1'b0;
    assign dfi.phyupd_ack  = 1'b0;
    assign dfi.lp_ctrl_ack = 1'b0;
    assign dfi.init_complete = 1'b1;  // PHY always ready for this env

    // -------------------------------------------------------------------------
    // PHY read-return model (dfi_clk domain).
    // Mirrors the Icarus tb logic exactly:
    //   - dfi.rddata_en assertion triggers a MC_CL-cycle countdown.
    //   - On expiry, pop one address from phy_addr_mbox and drive rddata.
    //
    // phy_addr_mbox is shared with the AXI driver (via config_db).
    // The driver pushes one address per AR beat when arready fires.
    // -------------------------------------------------------------------------
    mailbox #(logic [C_AXI_ADDR_WIDTH-1:0]) phy_addr_mbox = new();

    logic [7:0]                   phy_rd_lat;
    logic [C_AXI_ADDR_WIDTH-1:0]  phy_beat_addr;

    initial begin
        dfi.rddata       = '0;
        dfi.rddata_valid = 1'b0;
        phy_rd_lat       = 8'd0;
        phy_beat_addr    = '0;
    end

    always @(posedge dfi_clk or negedge dfi_rst_n) begin
        if (!dfi_rst_n) begin
            dfi.rddata_valid <= 1'b0;
            dfi.rddata       <= '0;
            phy_rd_lat       <= 8'd0;
        end else begin
            dfi.rddata_valid <= 1'b0;
            if (dfi.rddata_en)
                phy_rd_lat <= MC_CL[7:0];
            else if (phy_rd_lat != 8'd0) begin
                if (phy_rd_lat == 8'd1) begin
                    logic [C_AXI_ADDR_WIDTH-1:0] addr;
                    // Non-blocking get — if mbox is empty, addr = 0 (shouldn't happen)
                    if (phy_addr_mbox.try_get(addr)) begin
                        dfi.rddata_valid <= 1'b1;
                        dfi.rddata       <= {32'hA5A5A5A5, 14'h0, addr[DFI_ADDR_WIDTH-1:0]};
                    end
                    phy_rd_lat <= 8'd0;
                end else
                    phy_rd_lat <= phy_rd_lat - 8'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // UVM run
    // -------------------------------------------------------------------------
    initial begin
        // Publish virtual interfaces to config_db.
        uvm_config_db #(virtual axi4_if #(
            .ADDR_W(C_AXI_ADDR_WIDTH),
            .DATA_W(C_AXI_DATA_WIDTH),
            .ID_W  (C_AXI_ID_WIDTH)))::set(null, "uvm_test_top.*", "axi_vif", axi_if);

        uvm_config_db #(virtual dfi_if #(
            .ADDR_W(DFI_ADDR_WIDTH),
            .BANK_W(DFI_BANK_WIDTH)))::set(null, "uvm_test_top.*", "dfi_vif", dfi);

        // Publish shared PHY address mailbox for the AXI driver.
        uvm_config_db #(mailbox #(logic [C_AXI_ADDR_WIDTH-1:0]))::set(
            null, "uvm_test_top.*", "phy_addr_mbox", phy_addr_mbox);

        run_test();  // selects test via +UVM_TESTNAME=<test>
    end

    // -------------------------------------------------------------------------
    // Optional VCD dump (+vcd on command line)
    // -------------------------------------------------------------------------
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/tb_top.vcd");
            $dumpvars(0, tb_top);
        end
    end

    // -------------------------------------------------------------------------
    // Hard wall-clock limit (safety net independent of UVM timeout).
    // Overridden from the outside by +define+TB_TIMEOUT_NS=<n>.
    // -------------------------------------------------------------------------
`ifndef TB_TIMEOUT_NS
  `define TB_TIMEOUT_NS 600_000_000
`endif
    initial begin
        #(`TB_TIMEOUT_NS);
        $fatal(1, "tb_top: hard simulation timeout at %0t", $time);
    end

endmodule
