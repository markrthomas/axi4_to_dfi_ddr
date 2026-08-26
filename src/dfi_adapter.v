// dfi_adapter.v — dfi_clk-side DFI presentation: SDRAM MC + optional init pulse + tied sidebands.
`timescale 1ns / 1ps

module dfi_adapter #(
    parameter integer C_AXI_ADDR_WIDTH = 32,
    parameter integer C_AXI_DATA_WIDTH = 64,
    parameter integer C_AXI_ID_WIDTH   = 4,
    parameter integer DFI_ADDR_WIDTH = 18,
    parameter integer DFI_BANK_WIDTH = 3,
    parameter integer DFI_DATA_WIDTH = 64,
    parameter integer DFI_MASK_WIDTH = DFI_DATA_WIDTH / 8,
    parameter integer DFI_CS_WIDTH   = 1,
    parameter integer DFI_ODT_WIDTH  = 1,
    parameter integer DFI_CKE_WIDTH  = 1,
    parameter integer CDC_FIFO_DEPTH = 8,
    parameter integer DFI_WRITE_ACK_CYCLES = 4,
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
    parameter integer WREQ_W       = 1 + C_AXI_ID_WIDTH + C_AXI_ADDR_WIDTH +
                                     C_AXI_DATA_WIDTH + (C_AXI_DATA_WIDTH / 8),
    parameter integer RREQ_W       = 8 + C_AXI_ID_WIDTH + C_AXI_ADDR_WIDTH,
    parameter integer BRESP_FIFO_W = C_AXI_ID_WIDTH,
    parameter integer RRESP_FIFO_W = 1 + 1 + C_AXI_ID_WIDTH + C_AXI_DATA_WIDTH
) (
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

    output wire  [DFI_ADDR_WIDTH-1:0]    dfi_address,
    output wire  [DFI_BANK_WIDTH-1:0]    dfi_bank,
    output wire                          dfi_ras_n,
    output wire                          dfi_cas_n,
    output wire                          dfi_we_n,
    output wire  [DFI_CS_WIDTH-1:0]      dfi_cs_n,
    output wire  [DFI_ODT_WIDTH-1:0]    dfi_odt,
    output wire  [DFI_CKE_WIDTH-1:0]    dfi_cke,
    output wire                          dfi_act_n,

    output wire  [DFI_DATA_WIDTH-1:0]   dfi_wrdata,
    output wire  [DFI_MASK_WIDTH-1:0]   dfi_wrdata_mask,
    output wire                          dfi_wrdata_en,

    input  wire [DFI_DATA_WIDTH-1:0]    dfi_rddata,
    input  wire                          dfi_rddata_valid,
    output wire                          dfi_rddata_en,

    input  wire [WREQ_W-1:0]             mc_wreq_rdata,
    input  wire                          mc_wreq_empty,
    output wire                          mc_wreq_rd_en,

    input  wire [RREQ_W-1:0]             mc_rreq_rdata,
    input  wire                          mc_rreq_empty,
    output wire                          mc_rreq_rd_en,

    input  wire                          mc_bresp_full,
    output wire                          mc_bresp_wr_en,
    output wire [BRESP_FIFO_W-1:0]       mc_bresp_wr_data,

    input  wire                          mc_rresp_full,
    output wire                          mc_rresp_wr_en,
    output wire [RRESP_FIFO_W-1:0]       mc_rresp_wr_data
);

    assign dfi_ctrlupd_req  = 1'b0;
    assign dfi_phyupd_req   = 1'b0;
    assign dfi_lp_ctrl_req  = 1'b0;

    reg                      dfi_init_start_q;
    reg  [15:0]              dfi_init_start_ctr;

    assign dfi_init_start = (DFI_INIT_START_CYCLES > 0) ? dfi_init_start_q : 1'b0;

    always @(posedge dfi_clk or negedge dfi_rst_n) begin
        if (!dfi_rst_n) begin
            dfi_init_start_q   <= 1'b0;
            dfi_init_start_ctr <= DFI_INIT_START_CYCLES[15:0];
        end else if (dfi_init_start_ctr != 16'd0) begin
            dfi_init_start_q   <= 1'b1;
            dfi_init_start_ctr <= dfi_init_start_ctr - 16'd1;
        end else
            dfi_init_start_q <= 1'b0;
    end

    wire [DFI_ADDR_WIDTH-1:0] mc_dfi_address;
    wire [DFI_BANK_WIDTH-1:0] mc_dfi_bank;
    wire                      mc_dfi_ras_n;
    wire                      mc_dfi_cas_n;
    wire                      mc_dfi_we_n;
    wire [DFI_CS_WIDTH-1:0]   mc_dfi_cs_n;
    wire [DFI_ODT_WIDTH-1:0]  mc_dfi_odt;
    wire [DFI_CKE_WIDTH-1:0]  mc_dfi_cke;
    wire                      mc_dfi_act_n;
    wire [DFI_DATA_WIDTH-1:0] mc_dfi_wrdata;
    wire [DFI_MASK_WIDTH-1:0] mc_dfi_wrdata_mask;
    wire                      mc_dfi_wrdata_en;
    wire                      mc_dfi_rddata_en;

    mc_dfi_scheduler #(
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
        .WREQ_W                (WREQ_W),
        .RREQ_W                (RREQ_W),
        .BRESP_FIFO_W          (BRESP_FIFO_W),
        .RRESP_FIFO_W          (RRESP_FIFO_W)
    ) u_mc (
        .dfi_clk               (dfi_clk),
        .dfi_rst_n             (dfi_rst_n),
        .dfi_init_complete     (dfi_init_complete),
        .wreq_rdata            (mc_wreq_rdata),
        .wreq_empty            (mc_wreq_empty),
        .wreq_rd_en            (mc_wreq_rd_en),
        .rreq_rdata            (mc_rreq_rdata),
        .rreq_empty            (mc_rreq_empty),
        .rreq_rd_en            (mc_rreq_rd_en),
        .dfi_rddata            (dfi_rddata),
        .dfi_rddata_valid      (dfi_rddata_valid),
        .bresp_full            (mc_bresp_full),
        .rresp_full            (mc_rresp_full),
        .dfi_address           (mc_dfi_address),
        .dfi_bank              (mc_dfi_bank),
        .dfi_ras_n             (mc_dfi_ras_n),
        .dfi_cas_n             (mc_dfi_cas_n),
        .dfi_we_n              (mc_dfi_we_n),
        .dfi_cs_n              (mc_dfi_cs_n),
        .dfi_odt               (mc_dfi_odt),
        .dfi_cke               (mc_dfi_cke),
        .dfi_act_n             (mc_dfi_act_n),
        .dfi_wrdata            (mc_dfi_wrdata),
        .dfi_wrdata_mask       (mc_dfi_wrdata_mask),
        .dfi_wrdata_en         (mc_dfi_wrdata_en),
        .dfi_rddata_en         (mc_dfi_rddata_en),
        .bresp_wr_en           (mc_bresp_wr_en),
        .bresp_wr_data         (mc_bresp_wr_data),
        .rresp_wr_en           (mc_rresp_wr_en),
        .rresp_wr_data         (mc_rresp_wr_data)
    );

    assign dfi_address     = mc_dfi_address;
    assign dfi_bank        = mc_dfi_bank;
    assign dfi_ras_n       = mc_dfi_ras_n;
    assign dfi_cas_n       = mc_dfi_cas_n;
    assign dfi_we_n        = mc_dfi_we_n;
    assign dfi_cs_n        = mc_dfi_cs_n;
    assign dfi_odt         = mc_dfi_odt;
    assign dfi_cke         = mc_dfi_cke;
    assign dfi_act_n       = mc_dfi_act_n;
    assign dfi_wrdata      = mc_dfi_wrdata;
    assign dfi_wrdata_mask = mc_dfi_wrdata_mask;
    assign dfi_wrdata_en   = mc_dfi_wrdata_en;
    assign dfi_rddata_en   = mc_dfi_rddata_en;

endmodule
