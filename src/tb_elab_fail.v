//=============================================================================
// tb_elab_fail.v — expect axi4_to_dfi_bridge / async_fifo_gray elaboration $finish
//
// Each top module only instantiates a mis-parameterized block. Makefile runs
// vvp and greps for "ERROR:" on stdout (see test/Makefile elab-fail-*).
//=============================================================================

`timescale 1ns / 1ps

// C_AXI_DATA_WIDTH != DFI_DATA_WIDTH
module tb_elab_fail_width;
    wire aclk, aresetn;
    assign aclk = 1'b0;
    assign aresetn = 1'b0;
    axi4_to_dfi_bridge #(
        .C_AXI_DATA_WIDTH(32),
        .DFI_DATA_WIDTH  (64),
        .DFI_MASK_WIDTH   (8)
    ) dut (
        .axi_aclk(aclk), .axi_aresetn(aresetn),
        .s_axi_awid(4'b0), .s_axi_awaddr(32'b0), .s_axi_awlen(8'b0), .s_axi_awsize(3'd2),
        .s_axi_awburst(2'b01), .s_axi_awlock(1'b0), .s_axi_awcache(4'b0), .s_axi_awprot(3'b0),
        .s_axi_awqos(4'b0), .s_axi_awregion(4'b0), .s_axi_awuser(1'b0), .s_axi_awvalid(1'b0),
        .s_axi_awready(),
        .s_axi_wdata(32'b0), .s_axi_wstrb(4'b0), .s_axi_wlast(1'b0), .s_axi_wuser(1'b0),
        .s_axi_wvalid(1'b0), .s_axi_wready(),
        .s_axi_bid(), .s_axi_bresp(), .s_axi_buser(), .s_axi_bvalid(), .s_axi_bready(1'b0),
        .s_axi_arid(4'b0), .s_axi_araddr(32'b0), .s_axi_arlen(8'b0), .s_axi_arsize(3'd2),
        .s_axi_arburst(2'b01), .s_axi_arlock(1'b0), .s_axi_arcache(4'b0), .s_axi_arprot(3'b0),
        .s_axi_arqos(4'b0), .s_axi_arregion(4'b0), .s_axi_aruser(1'b0), .s_axi_arvalid(1'b0),
        .s_axi_arready(),
        .s_axi_rid(), .s_axi_rdata(), .s_axi_rresp(), .s_axi_rlast(), .s_axi_ruser(), .s_axi_rvalid(),
        .s_axi_rready(1'b0),
        .dfi_clk(aclk), .dfi_rst_n(aresetn),
        .dfi_ctrlupd_req(), .dfi_ctrlupd_ack(1'b0), .dfi_phyupd_req(), .dfi_phyupd_ack(1'b0),
        .dfi_lp_ctrl_req(), .dfi_lp_ctrl_ack(1'b0), .dfi_init_start(), .dfi_init_complete(1'b0),
        .dfi_address(), .dfi_bank(), .dfi_ras_n(), .dfi_cas_n(), .dfi_we_n(), .dfi_cs_n(),
        .dfi_odt(), .dfi_cke(), .dfi_act_n(),
        .dfi_wrdata(), .dfi_wrdata_mask(), .dfi_wrdata_en(), .dfi_rddata(64'b0),
        .dfi_rddata_valid(1'b0), .dfi_rddata_en()
    );
endmodule

// CDC_FIFO_DEPTH not power of two
module tb_elab_fail_depth;
    wire aclk, aresetn;
    assign aclk = 1'b0;
    assign aresetn = 1'b0;
    axi4_to_dfi_bridge #(
        .CDC_FIFO_DEPTH(9),
        .DFI_INIT_START_CYCLES(0)
    ) dut (
        .axi_aclk(aclk), .axi_aresetn(aresetn),
        .s_axi_awid(4'b0), .s_axi_awaddr(32'b0), .s_axi_awlen(8'b0), .s_axi_awsize(3'd3),
        .s_axi_awburst(2'b01), .s_axi_awlock(1'b0), .s_axi_awcache(4'b0), .s_axi_awprot(3'b0),
        .s_axi_awqos(4'b0), .s_axi_awregion(4'b0), .s_axi_awuser(1'b0), .s_axi_awvalid(1'b0),
        .s_axi_awready(),
        .s_axi_wdata(64'b0), .s_axi_wstrb(8'b0), .s_axi_wlast(1'b0), .s_axi_wuser(1'b0),
        .s_axi_wvalid(1'b0), .s_axi_wready(),
        .s_axi_bid(), .s_axi_bresp(), .s_axi_buser(), .s_axi_bvalid(), .s_axi_bready(1'b0),
        .s_axi_arid(4'b0), .s_axi_araddr(32'b0), .s_axi_arlen(8'b0), .s_axi_arsize(3'd3),
        .s_axi_arburst(2'b01), .s_axi_arlock(1'b0), .s_axi_arcache(4'b0), .s_axi_arprot(3'b0),
        .s_axi_arqos(4'b0), .s_axi_arregion(4'b0), .s_axi_aruser(1'b0), .s_axi_arvalid(1'b0),
        .s_axi_arready(),
        .s_axi_rid(), .s_axi_rdata(), .s_axi_rresp(), .s_axi_rlast(), .s_axi_ruser(), .s_axi_rvalid(),
        .s_axi_rready(1'b0),
        .dfi_clk(aclk), .dfi_rst_n(aresetn),
        .dfi_ctrlupd_req(), .dfi_ctrlupd_ack(1'b0), .dfi_phyupd_req(), .dfi_phyupd_ack(1'b0),
        .dfi_lp_ctrl_req(), .dfi_lp_ctrl_ack(1'b0), .dfi_init_start(), .dfi_init_complete(1'b0),
        .dfi_address(), .dfi_bank(), .dfi_ras_n(), .dfi_cas_n(), .dfi_we_n(), .dfi_cs_n(),
        .dfi_odt(), .dfi_cke(), .dfi_act_n(),
        .dfi_wrdata(), .dfi_wrdata_mask(), .dfi_wrdata_en(), .dfi_rddata(64'b0),
        .dfi_rddata_valid(1'b0), .dfi_rddata_en()
    );
endmodule

// Bank+row+col fields exceed AXI address width
module tb_elab_fail_addrmap;
    wire aclk, aresetn;
    assign aclk = 1'b0;
    assign aresetn = 1'b0;
    axi4_to_dfi_bridge #(
        .C_AXI_ADDR_WIDTH      (16),
        .MC_COL_BITS           (10),
        .MC_ROW_BITS           (14),
        .DFI_BANK_WIDTH        (3),
        .DFI_INIT_START_CYCLES (0)
    ) dut (
        .axi_aclk(aclk), .axi_aresetn(aresetn),
        .s_axi_awid(4'b0), .s_axi_awaddr(16'b0), .s_axi_awlen(8'b0), .s_axi_awsize(3'd3),
        .s_axi_awburst(2'b01), .s_axi_awlock(1'b0), .s_axi_awcache(4'b0), .s_axi_awprot(3'b0),
        .s_axi_awqos(4'b0), .s_axi_awregion(4'b0), .s_axi_awuser(1'b0), .s_axi_awvalid(1'b0),
        .s_axi_awready(),
        .s_axi_wdata(64'b0), .s_axi_wstrb(8'b0), .s_axi_wlast(1'b0), .s_axi_wuser(1'b0),
        .s_axi_wvalid(1'b0), .s_axi_wready(),
        .s_axi_bid(), .s_axi_bresp(), .s_axi_buser(), .s_axi_bvalid(), .s_axi_bready(1'b0),
        .s_axi_arid(4'b0), .s_axi_araddr(16'b0), .s_axi_arlen(8'b0), .s_axi_arsize(3'd3),
        .s_axi_arburst(2'b01), .s_axi_arlock(1'b0), .s_axi_arcache(4'b0), .s_axi_arprot(3'b0),
        .s_axi_arqos(4'b0), .s_axi_arregion(4'b0), .s_axi_aruser(1'b0), .s_axi_arvalid(1'b0),
        .s_axi_arready(),
        .s_axi_rid(), .s_axi_rdata(), .s_axi_rresp(), .s_axi_rlast(), .s_axi_ruser(), .s_axi_rvalid(),
        .s_axi_rready(1'b0),
        .dfi_clk(aclk), .dfi_rst_n(aresetn),
        .dfi_ctrlupd_req(), .dfi_ctrlupd_ack(1'b0), .dfi_phyupd_req(), .dfi_phyupd_ack(1'b0),
        .dfi_lp_ctrl_req(), .dfi_lp_ctrl_ack(1'b0), .dfi_init_start(), .dfi_init_complete(1'b0),
        .dfi_address(), .dfi_bank(), .dfi_ras_n(), .dfi_cas_n(), .dfi_we_n(), .dfi_cs_n(),
        .dfi_odt(), .dfi_cke(), .dfi_act_n(),
        .dfi_wrdata(), .dfi_wrdata_mask(), .dfi_wrdata_en(), .dfi_rddata(64'b0),
        .dfi_rddata_valid(1'b0), .dfi_rddata_en()
    );
endmodule

// async_fifo_gray DEPTH not power of two (standalone instance)
module tb_elab_fail_fifo;
    wire        wclk;
    wire        wrst;
    wire        wf, re;
    wire [7:0]  rd;
    assign wclk = 1'b0;
    assign wrst = 1'b0;
    async_fifo_gray #(
        .WIDTH(8),
        .DEPTH(9)
    ) u (
        .wr_clk   (wclk),
        .wr_rst_n (wrst),
        .wr_en    (1'b0),
        .wr_data  (8'b0),
        .wr_full  (wf),
        .rd_clk   (wclk),
        .rd_rst_n (wrst),
        .rd_en    (1'b0),
        .rd_data  (rd),
        .rd_empty (re)
    );
endmodule
