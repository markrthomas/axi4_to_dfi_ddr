//=============================================================================
// axi4_to_dfi_bridge.v
//
// AXI4 slave (AMBA AXI4, ARM IHI0022) to DFI memory-controller/PHY signals
// (JEDEC DFI 4.0 command + write/read data plane; compatible subset with
//  DFI 5.x which keeps the same dfi_* naming for this path).
//
// Tooling: Icarus Verilog — compile in order: cdc_fifo_lib.v, mc_dfi_scheduler.v,
//   axi4_bridge_frontend.v, dfi_adapter.v, then this file (see test/Makefile SOURCES).
//
// Structure: **axi4_bridge_frontend** (AXI + CDC FIFOs + B/R ordering) and
//   **dfi_adapter** (MC scheduler + DFI sidebands + optional dfi_init_start pulse).
//=============================================================================

`timescale 1ns / 1ps

module axi4_to_dfi_bridge #(
    parameter integer C_AXI_ADDR_WIDTH = 32,
    parameter integer C_AXI_DATA_WIDTH = 64,
    parameter integer C_AXI_ID_WIDTH   = 4,
    parameter integer C_AXI_AWUSER_WIDTH = 1,
    parameter integer C_AXI_WUSER_WIDTH  = 1,
    parameter integer C_AXI_BUSER_WIDTH  = 1,
    parameter integer C_AXI_ARUSER_WIDTH = 1,
    parameter integer C_AXI_RUSER_WIDTH  = 1,

    parameter integer DFI_ADDR_WIDTH = 18,
    parameter integer DFI_BANK_WIDTH = 3,
    parameter integer DFI_DATA_WIDTH = 64,
    parameter integer DFI_MASK_WIDTH = DFI_DATA_WIDTH / 8,
    parameter integer DFI_CS_WIDTH   = 1,
    parameter integer DFI_ODT_WIDTH  = 1,
    parameter integer DFI_CKE_WIDTH  = 1,

    parameter integer CDC_FIFO_DEPTH = 8,

    parameter integer DFI_WRITE_ACK_CYCLES = 4,
    parameter integer DFI_READ_DATA_CYCLES = 6,

    parameter integer MC_COL_BITS  = 10,
    parameter integer MC_ROW_BITS  = 14,
    parameter integer MC_T_RP      = 4,
    parameter integer MC_T_RCD     = 4,
    parameter integer MC_T_RAS     = 0,
    parameter integer MC_T_WR      = 0,
    parameter integer MC_CL        = 6,
    parameter integer MC_RD_DV_MAX = 16,

    parameter integer MC_REFRESH_INTERVAL = 0,
    parameter integer MC_T_RFC     = 0,

    parameter integer DFI_INIT_START_CYCLES = 0,

    parameter integer C_MAX_WRITE_AWLEN = 3,
    parameter integer C_MAX_READ_ARLEN = 3
) (
    input  wire                          axi_aclk,
    input  wire                          axi_aresetn,

    input  wire [C_AXI_ID_WIDTH-1:0]     s_axi_awid,
    input  wire [C_AXI_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [7:0]                    s_axi_awlen,
    input  wire [2:0]                    s_axi_awsize,
    input  wire [1:0]                    s_axi_awburst,
    input  wire                          s_axi_awlock,
    input  wire [3:0]                    s_axi_awcache,
    input  wire [2:0]                    s_axi_awprot,
    input  wire [3:0]                    s_axi_awqos,
    input  wire [3:0]                    s_axi_awregion,
    input  wire [C_AXI_AWUSER_WIDTH-1:0] s_axi_awuser,
    input  wire                          s_axi_awvalid,
    output wire                          s_axi_awready,

    input  wire [C_AXI_DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [C_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                          s_axi_wlast,
    input  wire [C_AXI_WUSER_WIDTH-1:0]  s_axi_wuser,
    input  wire                          s_axi_wvalid,
    output wire                          s_axi_wready,

    output wire [C_AXI_ID_WIDTH-1:0]     s_axi_bid,
    output wire [1:0]                    s_axi_bresp,
    output wire [C_AXI_BUSER_WIDTH-1:0]  s_axi_buser,
    output wire                          s_axi_bvalid,
    input  wire                          s_axi_bready,

    input  wire [C_AXI_ID_WIDTH-1:0]     s_axi_arid,
    input  wire [C_AXI_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [7:0]                    s_axi_arlen,
    input  wire [2:0]                    s_axi_arsize,
    input  wire [1:0]                    s_axi_arburst,
    input  wire                          s_axi_arlock,
    input  wire [3:0]                    s_axi_arcache,
    input  wire [2:0]                    s_axi_arprot,
    input  wire [3:0]                    s_axi_arqos,
    input  wire [3:0]                    s_axi_arregion,
    input  wire [C_AXI_ARUSER_WIDTH-1:0] s_axi_aruser,
    input  wire                          s_axi_arvalid,
    output wire                          s_axi_arready,

    output wire [C_AXI_ID_WIDTH-1:0]     s_axi_rid,
    output wire [C_AXI_DATA_WIDTH-1:0]   s_axi_rdata,
    output wire [1:0]                    s_axi_rresp,
    output wire                          s_axi_rlast,
    output wire [C_AXI_RUSER_WIDTH-1:0]  s_axi_ruser,
    output wire                          s_axi_rvalid,
    input  wire                          s_axi_rready,

    input  wire                          dfi_clk,
    input  wire                          dfi_rst_n,

    output wire                          dfi_ctrlupd_req,
    input  wire                          dfi_ctrlupd_ack,
    output wire                          dfi_phyupd_req,
    input  wire                          dfi_phyupd_ack,
    output wire                          dfi_lp_ctrl_req,
    input  wire                          dfi_lp_ctrl_ack,
    output wire                          dfi_init_start,
    input  wire                          dfi_init_complete,

    output wire  [DFI_ADDR_WIDTH-1:0]     dfi_address,
    output wire  [DFI_BANK_WIDTH-1:0]    dfi_bank,
    output wire                           dfi_ras_n,
    output wire                           dfi_cas_n,
    output wire                           dfi_we_n,
    output wire  [DFI_CS_WIDTH-1:0]       dfi_cs_n,
    output wire  [DFI_ODT_WIDTH-1:0]     dfi_odt,
    output wire  [DFI_CKE_WIDTH-1:0]     dfi_cke,
    output wire                           dfi_act_n,

    output wire  [DFI_DATA_WIDTH-1:0]    dfi_wrdata,
    output wire  [DFI_MASK_WIDTH-1:0]    dfi_wrdata_mask,
    output wire                           dfi_wrdata_en,

    input  wire [DFI_DATA_WIDTH-1:0]     dfi_rddata,
    input  wire                          dfi_rddata_valid,
    output wire                           dfi_rddata_en
);

    localparam integer STROBE_W = C_AXI_DATA_WIDTH / 8;
    localparam integer WREQ_W = 1 + C_AXI_ID_WIDTH + C_AXI_ADDR_WIDTH + C_AXI_DATA_WIDTH + STROBE_W;
    localparam integer RREQ_W = 8 + C_AXI_ID_WIDTH + C_AXI_ADDR_WIDTH;
    localparam integer BRESP_FIFO_W = C_AXI_ID_WIDTH;
    localparam integer RRESP_FIFO_W = 1 + 1 + C_AXI_ID_WIDTH + C_AXI_DATA_WIDTH;

    initial begin
        if (C_AXI_DATA_WIDTH != DFI_DATA_WIDTH) begin
            $display("ERROR: axi4_to_dfi_bridge: C_AXI_DATA_WIDTH (%0d) must equal DFI_DATA_WIDTH (%0d) (no width adapter)",
                     C_AXI_DATA_WIDTH, DFI_DATA_WIDTH);
            $finish(1);
        end
        if ((C_AXI_DATA_WIDTH % 8) != 0) begin
            $display("ERROR: axi4_to_dfi_bridge: C_AXI_DATA_WIDTH (%0d) must be a multiple of 8", C_AXI_DATA_WIDTH);
            $finish(1);
        end
        if (DFI_MASK_WIDTH != (C_AXI_DATA_WIDTH / 8)) begin
            $display("ERROR: axi4_to_dfi_bridge: DFI_MASK_WIDTH (%0d) must equal C_AXI_DATA_WIDTH/8 (%0d)",
                     DFI_MASK_WIDTH, C_AXI_DATA_WIDTH / 8);
            $finish(1);
        end
        if ((MC_COL_BITS + MC_ROW_BITS + DFI_BANK_WIDTH) > C_AXI_ADDR_WIDTH) begin
            $display("ERROR: axi4_to_dfi_bridge: MC_COL_BITS+MC_ROW_BITS+DFI_BANK_WIDTH (%0d+%0d+%0d) exceeds C_AXI_ADDR_WIDTH (%0d)",
                     MC_COL_BITS, MC_ROW_BITS, DFI_BANK_WIDTH, C_AXI_ADDR_WIDTH);
            $finish(1);
        end
        if (MC_COL_BITS < 1 || MC_ROW_BITS < 1) begin
            $display("ERROR: axi4_to_dfi_bridge: MC_COL_BITS and MC_ROW_BITS must be >= 1 (got %0d, %0d)",
                     MC_COL_BITS, MC_ROW_BITS);
            $finish(1);
        end
        if (DFI_ADDR_WIDTH < MC_ROW_BITS || DFI_ADDR_WIDTH < MC_COL_BITS) begin
            $display("ERROR: axi4_to_dfi_bridge: DFI_ADDR_WIDTH (%0d) must be >= MC_ROW_BITS (%0d) and >= MC_COL_BITS (%0d)",
                     DFI_ADDR_WIDTH, MC_ROW_BITS, MC_COL_BITS);
            $finish(1);
        end
        if (CDC_FIFO_DEPTH < 2 || ((CDC_FIFO_DEPTH & (CDC_FIFO_DEPTH - 1)) != 0)) begin
            $display("ERROR: axi4_to_dfi_bridge: CDC_FIFO_DEPTH (%0d) must be a power of two >= 2", CDC_FIFO_DEPTH);
            $finish(1);
        end
        if (DFI_BANK_WIDTH > 24) begin
            $display("ERROR: axi4_to_dfi_bridge: DFI_BANK_WIDTH (%0d) too large for implementation limits", DFI_BANK_WIDTH);
            $finish(1);
        end
        if (C_AXI_ID_WIDTH < 1) begin
            $display("ERROR: axi4_to_dfi_bridge: C_AXI_ID_WIDTH (%0d) must be >= 1", C_AXI_ID_WIDTH);
            $finish(1);
        end
        if (MC_T_RP < 0 || MC_T_RCD < 0 || MC_T_RAS < 0 || MC_T_WR < 0 || MC_CL < 0 || MC_RD_DV_MAX < 0 ||
            DFI_WRITE_ACK_CYCLES < 0) begin
            $display("ERROR: axi4_to_dfi_bridge: MC timing and DFI_WRITE_ACK_CYCLES must be >= 0");
            $finish(1);
        end
        if (MC_T_RP > 255 || MC_T_RCD > 255 || MC_T_RAS > 255 || MC_T_WR > 255 || MC_CL > 255 ||
            MC_RD_DV_MAX > 255 || DFI_WRITE_ACK_CYCLES > 255) begin
            $display("ERROR: axi4_to_dfi_bridge: MC_T_RP, MC_T_RCD, MC_T_RAS, MC_T_WR, MC_CL, MC_RD_DV_MAX, and DFI_WRITE_ACK_CYCLES must be <= 255 (8-bit counters in RTL)");
            $finish(1);
        end
        if (DFI_INIT_START_CYCLES < 0 || DFI_INIT_START_CYCLES > 65535) begin
            $display("ERROR: axi4_to_dfi_bridge: DFI_INIT_START_CYCLES (%0d) must be in 0..65535", DFI_INIT_START_CYCLES);
            $finish(1);
        end
        if (MC_REFRESH_INTERVAL < 0) begin
            $display("ERROR: axi4_to_dfi_bridge: MC_REFRESH_INTERVAL (%0d) must be >= 0", MC_REFRESH_INTERVAL);
            $finish(1);
        end
        if (MC_T_RFC < 0 || MC_T_RFC > 65535) begin
            $display("ERROR: axi4_to_dfi_bridge: MC_T_RFC (%0d) must be in 0..65535 (16-bit counter in RTL)", MC_T_RFC);
            $finish(1);
        end
        if (C_MAX_WRITE_AWLEN < 0 || C_MAX_WRITE_AWLEN > 255) begin
            $display("ERROR: axi4_to_dfi_bridge: C_MAX_WRITE_AWLEN (%0d) must be in 0..255", C_MAX_WRITE_AWLEN);
            $finish(1);
        end
        if (C_MAX_READ_ARLEN < 0 || C_MAX_READ_ARLEN > 255) begin
            $display("ERROR: axi4_to_dfi_bridge: C_MAX_READ_ARLEN (%0d) must be in 0..255", C_MAX_READ_ARLEN);
            $finish(1);
        end
        if ((C_MAX_READ_ARLEN + 1) > CDC_FIFO_DEPTH) begin
            $display("ERROR: axi4_to_dfi_bridge: CDC_FIFO_DEPTH (%0d) must be >= C_MAX_READ_ARLEN+1 (%0d) for RRESP FIFO",
                     CDC_FIFO_DEPTH, C_MAX_READ_ARLEN + 1);
            $finish(1);
        end
    end

    wire [WREQ_W-1:0]             mc_wreq_rdata;
    wire                          mc_wreq_empty;
    wire                          mc_wreq_rd_en;
    wire [RREQ_W-1:0]             mc_rreq_rdata;
    wire                          mc_rreq_empty;
    wire                          mc_rreq_rd_en;
    wire                          mc_bresp_full;
    wire                          mc_bresp_wr_en;
    wire [BRESP_FIFO_W-1:0]       mc_bresp_wr_data;
    wire                          mc_rresp_full;
    wire                          mc_rresp_wr_en;
    wire [RRESP_FIFO_W-1:0]       mc_rresp_wr_data;

    axi4_bridge_frontend #(
        .C_AXI_ADDR_WIDTH      (C_AXI_ADDR_WIDTH),
        .C_AXI_DATA_WIDTH      (C_AXI_DATA_WIDTH),
        .C_AXI_ID_WIDTH        (C_AXI_ID_WIDTH),
        .C_AXI_AWUSER_WIDTH    (C_AXI_AWUSER_WIDTH),
        .C_AXI_WUSER_WIDTH     (C_AXI_WUSER_WIDTH),
        .C_AXI_BUSER_WIDTH     (C_AXI_BUSER_WIDTH),
        .C_AXI_ARUSER_WIDTH    (C_AXI_ARUSER_WIDTH),
        .C_AXI_RUSER_WIDTH     (C_AXI_RUSER_WIDTH),
        .CDC_FIFO_DEPTH        (CDC_FIFO_DEPTH),
        .MC_COL_BITS           (MC_COL_BITS),
        .MC_ROW_BITS           (MC_ROW_BITS),
        .DFI_BANK_WIDTH        (DFI_BANK_WIDTH),
        .C_MAX_WRITE_AWLEN     (C_MAX_WRITE_AWLEN),
        .C_MAX_READ_ARLEN      (C_MAX_READ_ARLEN),
        .WREQ_W                (WREQ_W),
        .RREQ_W                (RREQ_W),
        .BRESP_FIFO_W          (BRESP_FIFO_W),
        .RRESP_FIFO_W          (RRESP_FIFO_W)
    ) u_axi_fe (
        .axi_aclk              (axi_aclk),
        .axi_aresetn           (axi_aresetn),
        .s_axi_awid            (s_axi_awid),
        .s_axi_awaddr          (s_axi_awaddr),
        .s_axi_awlen           (s_axi_awlen),
        .s_axi_awsize          (s_axi_awsize),
        .s_axi_awburst         (s_axi_awburst),
        .s_axi_awlock          (s_axi_awlock),
        .s_axi_awcache         (s_axi_awcache),
        .s_axi_awprot          (s_axi_awprot),
        .s_axi_awqos           (s_axi_awqos),
        .s_axi_awregion        (s_axi_awregion),
        .s_axi_awuser          (s_axi_awuser),
        .s_axi_awvalid         (s_axi_awvalid),
        .s_axi_awready         (s_axi_awready),
        .s_axi_wdata           (s_axi_wdata),
        .s_axi_wstrb           (s_axi_wstrb),
        .s_axi_wlast           (s_axi_wlast),
        .s_axi_wuser           (s_axi_wuser),
        .s_axi_wvalid          (s_axi_wvalid),
        .s_axi_wready          (s_axi_wready),
        .s_axi_bid             (s_axi_bid),
        .s_axi_bresp           (s_axi_bresp),
        .s_axi_buser           (s_axi_buser),
        .s_axi_bvalid          (s_axi_bvalid),
        .s_axi_bready          (s_axi_bready),
        .s_axi_arid            (s_axi_arid),
        .s_axi_araddr          (s_axi_araddr),
        .s_axi_arlen           (s_axi_arlen),
        .s_axi_arsize          (s_axi_arsize),
        .s_axi_arburst         (s_axi_arburst),
        .s_axi_arlock          (s_axi_arlock),
        .s_axi_arcache         (s_axi_arcache),
        .s_axi_arprot          (s_axi_arprot),
        .s_axi_arqos           (s_axi_arqos),
        .s_axi_arregion        (s_axi_arregion),
        .s_axi_aruser          (s_axi_aruser),
        .s_axi_arvalid         (s_axi_arvalid),
        .s_axi_arready         (s_axi_arready),
        .s_axi_rid             (s_axi_rid),
        .s_axi_rdata           (s_axi_rdata),
        .s_axi_rresp           (s_axi_rresp),
        .s_axi_rlast           (s_axi_rlast),
        .s_axi_ruser           (s_axi_ruser),
        .s_axi_rvalid          (s_axi_rvalid),
        .s_axi_rready          (s_axi_rready),
        .dfi_clk               (dfi_clk),
        .dfi_rst_n             (dfi_rst_n),
        .mc_wreq_rdata         (mc_wreq_rdata),
        .mc_wreq_empty         (mc_wreq_empty),
        .mc_wreq_rd_en         (mc_wreq_rd_en),
        .mc_rreq_rdata         (mc_rreq_rdata),
        .mc_rreq_empty         (mc_rreq_empty),
        .mc_rreq_rd_en         (mc_rreq_rd_en),
        .mc_bresp_full         (mc_bresp_full),
        .mc_bresp_wr_en        (mc_bresp_wr_en),
        .mc_bresp_wr_data      (mc_bresp_wr_data),
        .mc_rresp_full         (mc_rresp_full),
        .mc_rresp_wr_en        (mc_rresp_wr_en),
        .mc_rresp_wr_data      (mc_rresp_wr_data)
    );

    dfi_adapter #(
        .C_AXI_ADDR_WIDTH      (C_AXI_ADDR_WIDTH),
        .C_AXI_DATA_WIDTH      (C_AXI_DATA_WIDTH),
        .C_AXI_ID_WIDTH        (C_AXI_ID_WIDTH),
        .DFI_ADDR_WIDTH        (DFI_ADDR_WIDTH),
        .DFI_BANK_WIDTH        (DFI_BANK_WIDTH),
        .DFI_DATA_WIDTH        (DFI_DATA_WIDTH),
        .DFI_MASK_WIDTH        (DFI_MASK_WIDTH),
        .DFI_CS_WIDTH          (DFI_CS_WIDTH),
        .DFI_ODT_WIDTH         (DFI_ODT_WIDTH),
        .DFI_CKE_WIDTH         (DFI_CKE_WIDTH),
        .CDC_FIFO_DEPTH        (CDC_FIFO_DEPTH),
        .DFI_WRITE_ACK_CYCLES  (DFI_WRITE_ACK_CYCLES),
        .MC_COL_BITS           (MC_COL_BITS),
        .MC_ROW_BITS           (MC_ROW_BITS),
        .MC_T_RP               (MC_T_RP),
        .MC_T_RCD              (MC_T_RCD),
        .MC_T_RAS              (MC_T_RAS),
        .MC_T_WR               (MC_T_WR),
        .MC_CL                 (MC_CL),
        .MC_RD_DV_MAX          (MC_RD_DV_MAX),
        .MC_REFRESH_INTERVAL   (MC_REFRESH_INTERVAL),
        .MC_T_RFC              (MC_T_RFC),
        .DFI_INIT_START_CYCLES (DFI_INIT_START_CYCLES),
        .WREQ_W                (WREQ_W),
        .RREQ_W                (RREQ_W),
        .BRESP_FIFO_W          (BRESP_FIFO_W),
        .RRESP_FIFO_W          (RRESP_FIFO_W)
    ) u_dfi (
        .dfi_clk               (dfi_clk),
        .dfi_rst_n             (dfi_rst_n),
        .dfi_ctrlupd_req       (dfi_ctrlupd_req),
        .dfi_ctrlupd_ack       (dfi_ctrlupd_ack),
        .dfi_phyupd_req        (dfi_phyupd_req),
        .dfi_phyupd_ack        (dfi_phyupd_ack),
        .dfi_lp_ctrl_req       (dfi_lp_ctrl_req),
        .dfi_lp_ctrl_ack       (dfi_lp_ctrl_ack),
        .dfi_init_start        (dfi_init_start),
        .dfi_init_complete     (dfi_init_complete),
        .dfi_address           (dfi_address),
        .dfi_bank              (dfi_bank),
        .dfi_ras_n             (dfi_ras_n),
        .dfi_cas_n             (dfi_cas_n),
        .dfi_we_n              (dfi_we_n),
        .dfi_cs_n              (dfi_cs_n),
        .dfi_odt               (dfi_odt),
        .dfi_cke               (dfi_cke),
        .dfi_act_n             (dfi_act_n),
        .dfi_wrdata            (dfi_wrdata),
        .dfi_wrdata_mask       (dfi_wrdata_mask),
        .dfi_wrdata_en         (dfi_wrdata_en),
        .dfi_rddata            (dfi_rddata),
        .dfi_rddata_valid      (dfi_rddata_valid),
        .dfi_rddata_en         (dfi_rddata_en),
        .mc_wreq_rdata         (mc_wreq_rdata),
        .mc_wreq_empty         (mc_wreq_empty),
        .mc_wreq_rd_en         (mc_wreq_rd_en),
        .mc_rreq_rdata         (mc_rreq_rdata),
        .mc_rreq_empty         (mc_rreq_empty),
        .mc_rreq_rd_en         (mc_rreq_rd_en),
        .mc_bresp_full         (mc_bresp_full),
        .mc_bresp_wr_en        (mc_bresp_wr_en),
        .mc_bresp_wr_data      (mc_bresp_wr_data),
        .mc_rresp_full         (mc_rresp_full),
        .mc_rresp_wr_en        (mc_rresp_wr_en),
        .mc_rresp_wr_data      (mc_rresp_wr_data)
    );

endmodule
