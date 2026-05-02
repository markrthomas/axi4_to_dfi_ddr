//=============================================================================
// axi4_to_dfi_bridge.v
//
// AXI4 slave (AMBA AXI4, ARM IHI0022) to DFI memory-controller/PHY signals
// (JEDEC DFI 4.0 command + write/read data plane; compatible subset with
//  DFI 5.x which keeps the same dfi_* naming for this path).
//
// Tooling: Icarus Verilog — compile cdc_fifo_lib.v, then mc_dfi_scheduler.v, then this file
//   (see test/Makefile SOURCES).
//
// Clock domains
//   - axi_aclk / axi_aresetn : AXI4 protocol and user-facing timing
//   - dfi_clk  / dfi_rst_n   : DFI-side timing (often 1:1 or ratioed to DRAM)
//
// Functional note: AXI4 handshaking, CDC, SLVERR for unsupported requests and
//  read-data timeout (no dfi_rddata_valid within MC_RD_DV_MAX).
// C_AXI_DATA_WIDTH must equal DFI_DATA_WIDTH and DFI_MASK_WIDTH must equal
//  C_AXI_DATA_WIDTH/8 (checked at elaboration); no byte-lane adapter.
// The dfi_clk domain includes an SDRAM-style open-page scheduler: per-bank
// row tracking, PRE (wrong row or closed), ACT, then READ/WRITE CAS with
// parameterized tRP, tRCD, MC_T_RAS (ACT to PRE), MC_T_WR (WRITE CAS to PRE),
// and MC_CL. Optional all-bank refresh walk
// (MC_REFRESH_INTERVAL, default 0 = off) issues PRE on any open bank then
// reloads the interval counter; multi-clock DFI phase buses (P0–P3) are not
// implemented. dfi_act_n is low only during ACT; optional
// dfi_init_start pulse after reset uses DFI_INIT_START_CYCLES (default 0).
//=============================================================================

`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// AXI4 -> DFI bridge (INCR write bursts up to C_MAX_WRITE_AWLEN; INCR read bursts
//  up to C_MAX_READ_ARLEN within one DRAM row)
//-----------------------------------------------------------------------------
module axi4_to_dfi_bridge #(
    parameter integer C_AXI_ADDR_WIDTH = 32,
    parameter integer C_AXI_DATA_WIDTH = 64,
    parameter integer C_AXI_ID_WIDTH   = 4,
    // USER widths must be >= 1 for portable Verilog port vectors (tie if unused).
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

    // PHY / response timing (dfi_clk cycles)
    parameter integer DFI_WRITE_ACK_CYCLES = 4,
    parameter integer DFI_READ_DATA_CYCLES = 6,

    // SDRAM-style scheduler: address map = { bank, row, col } in AXI byte address LSBs
    parameter integer MC_COL_BITS  = 10,
    parameter integer MC_ROW_BITS  = 14,
    parameter integer MC_T_RP      = 4,  // PRE to ACT
    parameter integer MC_T_RCD     = 4,  // ACT to READ/WRITE command
    // Min dfi_clk cycles from ACT command to PRE (same bank). 0 = no extra wait.
    parameter integer MC_T_RAS     = 0,
    // Min dfi_clk cycles from WRITE CAS to PRE (same bank). 0 = no extra wait.
    parameter integer MC_T_WR      = 0,
    parameter integer MC_CL        = 6,  // CAS to first read data (PHY should align)
    parameter integer MC_RD_DV_MAX = 16,  // cycles to wait for dfi_rddata_valid after CL

    // Refresh pacing (dfi_clk): when > 0, count down in fully idle gaps between commands
    // (mc_state==ST_IDLE, no request snapshot pending); at 0, walk banks 0..2^BANK-1 and
    // PRE any open row (same encoding as normal PRE), then reload to MC_REFRESH_INTERVAL.
    // 0 disables refresh (legacy behavior).
    parameter integer MC_REFRESH_INTERVAL = 0,

    // DFI sideband: pulse dfi_init_start for this many dfi_clk cycles after reset release (0 = tie off)
    parameter integer DFI_INIT_START_CYCLES = 0,

    // AXI write: max AWLEN for legal INCR bursts (0 = single-beat only; default 3 = up to 4 beats)
    parameter integer C_MAX_WRITE_AWLEN = 3,
    // AXI read: max ARLEN for legal INCR bursts (0 = single-beat only; burst must stay in one row)
    parameter integer C_MAX_READ_ARLEN = 3
) (
    // --- AXI4 clock / reset (AMBA AXI4) ---
    input  wire                          axi_aclk,
    input  wire                          axi_aresetn,

    // Write address channel
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

    // Write data channel
    input  wire [C_AXI_DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [C_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                          s_axi_wlast,
    input  wire [C_AXI_WUSER_WIDTH-1:0]  s_axi_wuser,
    input  wire                          s_axi_wvalid,
    output wire                          s_axi_wready,

    // Write response channel
    output wire [C_AXI_ID_WIDTH-1:0]     s_axi_bid,
    output wire [1:0]                    s_axi_bresp,
    output wire [C_AXI_BUSER_WIDTH-1:0]  s_axi_buser,
    output wire                          s_axi_bvalid,
    input  wire                          s_axi_bready,

    // Read address channel
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

    // Read data channel
    output wire [C_AXI_ID_WIDTH-1:0]     s_axi_rid,
    output wire [C_AXI_DATA_WIDTH-1:0]   s_axi_rdata,
    output wire [1:0]                    s_axi_rresp,
    output wire                          s_axi_rlast,
    output wire [C_AXI_RUSER_WIDTH-1:0]  s_axi_ruser,
    output wire                          s_axi_rvalid,
    input  wire                          s_axi_rready,

    // --- DFI clock / reset (DFI 4.0/5.x PHY-facing) ---
    input  wire                          dfi_clk,
    input  wire                          dfi_rst_n,

    // Optional DFI update / init handshakes (tie off if unused)
    output wire                          dfi_ctrlupd_req,
    input  wire                          dfi_ctrlupd_ack,
    output wire                          dfi_phyupd_req,
    input  wire                          dfi_phyupd_ack,
    output wire                          dfi_lp_ctrl_req,
    input  wire                          dfi_lp_ctrl_ack,
    output wire                          dfi_init_start,
    input  wire                          dfi_init_complete,

    // Command (DDR-style RAS/CAS/WE encoding on DFI)
    output wire  [DFI_ADDR_WIDTH-1:0]     dfi_address,
    output wire  [DFI_BANK_WIDTH-1:0]     dfi_bank,
    output wire                           dfi_ras_n,
    output wire                           dfi_cas_n,
    output wire                           dfi_we_n,
    output wire  [DFI_CS_WIDTH-1:0]       dfi_cs_n,
    output wire  [DFI_ODT_WIDTH-1:0]      dfi_odt,
    output wire  [DFI_CKE_WIDTH-1:0]      dfi_cke,
    output wire                           dfi_act_n,

    // Write data path
    output wire  [DFI_DATA_WIDTH-1:0]     dfi_wrdata,
    output wire  [DFI_MASK_WIDTH-1:0]     dfi_wrdata_mask,
    output wire                           dfi_wrdata_en,

    // Read data path
    input  wire [DFI_DATA_WIDTH-1:0]     dfi_rddata,
    input  wire                          dfi_rddata_valid,
    output wire                           dfi_rddata_en
);

    localparam integer STROBE_W = C_AXI_DATA_WIDTH / 8;

    // Tie optional DFI sideband signals (full PHY may drive these differently)
    assign dfi_ctrlupd_req  = 1'b0;
    assign dfi_phyupd_req   = 1'b0;
    assign dfi_lp_ctrl_req  = 1'b0;

    // Optional MC -> PHY init pulse (DFI: controller may pulse init_start during DRAM init)
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

    //-------------------------------------------------------------------------
    // FIFO payloads (packed)
    //-------------------------------------------------------------------------
    localparam integer WREQ_W = 1 + C_AXI_ID_WIDTH + C_AXI_ADDR_WIDTH + C_AXI_DATA_WIDTH + STROBE_W;
    // MSB = AXI WLAST for this beat; then id, addr, data, strb (one FIFO entry per W beat)

    localparam integer RREQ_W = 8 + C_AXI_ID_WIDTH + C_AXI_ADDR_WIDTH;
    // MSB: ARLEN (8); then ARID; then ARADDR (one FIFO entry per AR burst)

    localparam integer BRESP_FIFO_W = C_AXI_ID_WIDTH;
    // MSB: SLVERR from MC timeout; then RLAST; then ARID; then RDATA
    localparam integer RRESP_FIFO_W = 1 + 1 + C_AXI_ID_WIDTH + C_AXI_DATA_WIDTH;

    localparam [C_AXI_ADDR_WIDTH-1:0] WADDR_INCR = C_AXI_DATA_WIDTH / 8;

    //-------------------------------------------------------------------------
    // AXI: INCR writes up to C_MAX_WRITE_AWLEN; INCR reads up to C_MAX_READ_ARLEN (one row)
    //-------------------------------------------------------------------------
    wire aw_ok = (s_axi_awburst == 2'b01) && (s_axi_awlen <= C_MAX_WRITE_AWLEN) &&
                 (s_axi_awsize == $clog2(C_AXI_DATA_WIDTH/8));
    wire ar_ok_basic = (s_axi_arburst == 2'b01) && (s_axi_arlen <= C_MAX_READ_ARLEN) &&
                       (s_axi_arsize == $clog2(C_AXI_DATA_WIDTH/8));
    // INCR burst must not cross DRAM row (bank+row bits constant from first to last beat)
    wire [C_AXI_ADDR_WIDTH-1:0] ar_last_beat_addr =
        s_axi_araddr + ({{(C_AXI_ADDR_WIDTH-8){1'b0}}, s_axi_arlen} * WADDR_INCR);
    wire ar_in_one_row =
        ar_last_beat_addr[C_AXI_ADDR_WIDTH-1:MC_COL_BITS] == s_axi_araddr[C_AXI_ADDR_WIDTH-1:MC_COL_BITS];
    wire ar_ok = ar_ok_basic && ar_in_one_row;

    wire wreq_full;
    wire wreq_empty;
    wire wreq_rd_en;
    wire [WREQ_W-1:0] wreq_rdata;

    wire rreq_full;
    wire rreq_empty;
    wire rreq_rd_en;
    wire [RREQ_W-1:0] rreq_rdata;

    reg aw_hold_valid;
    reg [C_AXI_ID_WIDTH-1:0] aw_hold_id;
    reg [C_AXI_ADDR_WIDTH-1:0] aw_hold_addr;
    reg aw_hold_ok;
    reg [7:0] aw_hold_len;
    reg w_hold_valid;
    reg [C_AXI_DATA_WIDTH-1:0] w_hold_data;
    reg [STROBE_W-1:0] w_hold_strb;
    reg w_hold_last;

    reg bresp_err_valid;
    reg [C_AXI_ID_WIDTH-1:0] bresp_err_id;
    reg bresp_err_pending;
    reg [C_AXI_ID_WIDTH-1:0] bresp_err_pending_id;
    reg rresp_err_valid;
    reg [C_AXI_ID_WIDTH-1:0] rresp_err_id;
    reg rresp_err_pending;
    reg [C_AXI_ID_WIDTH-1:0] rresp_err_pending_id;

    // Legal responses can return later from the DFI domain. Keep local decode
    // errors pending until older legal same-channel responses have drained.
    reg [15:0] b_legal_outstanding;
    reg [15:0] r_legal_outstanding;

    reg write_err_active;
    reg write_err_wait_last;
    reg [7:0] write_err_beats_left;
    reg [C_AXI_ID_WIDTH-1:0] write_err_id;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire ar_fire = s_axi_arvalid && s_axi_arready;
    wire w_fire  = s_axi_wvalid && s_axi_wready;

    wire aw_pair_valid = aw_hold_valid || aw_fire;
    wire w_pair_valid  = w_hold_valid || w_fire;

    wire [C_AXI_ID_WIDTH-1:0] aw_pair_id =
        aw_hold_valid ? aw_hold_id : s_axi_awid;
    wire [C_AXI_ADDR_WIDTH-1:0] aw_pair_addr =
        aw_hold_valid ? aw_hold_addr : s_axi_awaddr;
    wire aw_pair_ok =
        aw_hold_valid ? aw_hold_ok : aw_ok;
    wire [7:0] aw_pair_len =
        aw_hold_valid ? aw_hold_len : s_axi_awlen;
    wire [C_AXI_DATA_WIDTH-1:0] w_pair_data =
        w_hold_valid ? w_hold_data : s_axi_wdata;
    wire [STROBE_W-1:0] w_pair_strb =
        w_hold_valid ? w_hold_strb : s_axi_wstrb;
    wire w_pair_last =
        w_hold_valid ? w_hold_last : s_axi_wlast;

    reg [7:0] w_axi_beat_idx;

    // Registered beat counter can be stale from a prior txn; same-cycle AW fire starts a new burst at 0
    wire [7:0] w_beat_effective = aw_fire ? 8'd0 : w_axi_beat_idx;
    wire wlast_expected = (w_beat_effective == aw_pair_len);
    wire wlast_bad      = aw_pair_valid && w_pair_valid && aw_pair_ok &&
                          (w_pair_last != wlast_expected);

    wire wreq_wr_en = aw_pair_valid && w_pair_valid && aw_pair_ok && !wlast_bad && !wreq_full;
    wire [WREQ_W-1:0] wreq_push_vec = {w_pair_last, aw_pair_id, aw_pair_addr, w_pair_data, w_pair_strb};
    wire write_pair_error = aw_pair_valid && w_pair_valid && (!aw_pair_ok || wlast_bad);
    wire write_pair_error_needs_drain = (aw_pair_len != 8'd0) ||
                                        ((aw_pair_len == 8'd0) && !w_pair_last);
    wire write_err_done = write_err_active && w_fire &&
                          ((write_err_wait_last && s_axi_wlast) ||
                           (!write_err_wait_last && (write_err_beats_left == 8'd1)));

    assign s_axi_awready = !aw_hold_valid && !write_err_active &&
                           !bresp_err_valid && !bresp_err_pending;
    assign s_axi_wready  = !w_hold_valid && !bresp_err_valid && !bresp_err_pending;
    async_fifo_gray #(
        .WIDTH (WREQ_W),
        .DEPTH (CDC_FIFO_DEPTH)
    ) u_fifo_wreq (
        .wr_clk   (axi_aclk),
        .wr_rst_n (axi_aresetn),
        .wr_en    (wreq_wr_en),
        .wr_data  (wreq_push_vec),
        .wr_full  (wreq_full),
        .rd_clk   (dfi_clk),
        .rd_rst_n (dfi_rst_n),
        .rd_en    (wreq_rd_en),
        .rd_data  (wreq_rdata),
        .rd_empty (wreq_empty)
    );

    wire rreq_wr_en = s_axi_arvalid && s_axi_arready && ar_ok;
    wire [RREQ_W-1:0] rreq_push = {s_axi_arlen, s_axi_arid, s_axi_araddr};

    assign s_axi_arready = ar_ok ? !rreq_full : (!rresp_err_valid && !rresp_err_pending);

    async_fifo_gray #(
        .WIDTH (RREQ_W),
        .DEPTH (CDC_FIFO_DEPTH)
    ) u_fifo_rreq (
        .wr_clk   (axi_aclk),
        .wr_rst_n (axi_aresetn),
        .wr_en    (rreq_wr_en),
        .wr_data  (rreq_push),
        .wr_full  (rreq_full),
        .rd_clk   (dfi_clk),
        .rd_rst_n (dfi_rst_n),
        .rd_en    (rreq_rd_en),
        .rd_data  (rreq_rdata),
        .rd_empty (rreq_empty)
    );

    //-------------------------------------------------------------------------
    // SDRAM open-page MC / DFI command timing (see mc_dfi_scheduler.v)
    //-------------------------------------------------------------------------
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

    wire bresp_full;
    wire rresp_full;
    wire bresp_wr_en;
    wire [BRESP_FIFO_W-1:0] bresp_wr_data;
    wire rresp_wr_en;
    wire [RRESP_FIFO_W-1:0] rresp_wr_data;

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
        .WREQ_W                (WREQ_W),
        .RREQ_W                (RREQ_W),
        .BRESP_FIFO_W          (BRESP_FIFO_W),
        .RRESP_FIFO_W          (RRESP_FIFO_W)
    ) u_mc (
        .dfi_clk               (dfi_clk),
        .dfi_rst_n             (dfi_rst_n),
        .dfi_init_complete     (dfi_init_complete),
        .wreq_rdata            (wreq_rdata),
        .wreq_empty            (wreq_empty),
        .wreq_rd_en            (wreq_rd_en),
        .rreq_rdata            (rreq_rdata),
        .rreq_empty            (rreq_empty),
        .rreq_rd_en            (rreq_rd_en),
        .dfi_rddata            (dfi_rddata),
        .dfi_rddata_valid      (dfi_rddata_valid),
        .bresp_full            (bresp_full),
        .rresp_full            (rresp_full),
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
        .dfi_rddata_en         (dfi_rddata_en),
        .bresp_wr_en           (bresp_wr_en),
        .bresp_wr_data         (bresp_wr_data),
        .rresp_wr_en           (rresp_wr_en),
        .rresp_wr_data         (rresp_wr_data)
    );

    wire bresp_rd_en;
    wire bresp_empty;
    wire [BRESP_FIFO_W-1:0] bresp_rdata;

    wire rresp_rd_en;
    wire rresp_empty;
    wire [RRESP_FIFO_W-1:0] rresp_rdata;

    async_fifo_gray #(
        .WIDTH (BRESP_FIFO_W),
        .DEPTH (CDC_FIFO_DEPTH)
    ) u_fifo_bresp (
        .wr_clk   (dfi_clk),
        .wr_rst_n (dfi_rst_n),
        .wr_en    (bresp_wr_en),
        .wr_data  (bresp_wr_data),
        .wr_full  (bresp_full),
        .rd_clk   (axi_aclk),
        .rd_rst_n (axi_aresetn),
        .rd_en    (bresp_rd_en),
        .rd_data  (bresp_rdata),
        .rd_empty (bresp_empty)
    );

    async_fifo_gray #(
        .WIDTH (RRESP_FIFO_W),
        .DEPTH (CDC_FIFO_DEPTH)
    ) u_fifo_rresp (
        .wr_clk   (dfi_clk),
        .wr_rst_n (dfi_rst_n),
        .wr_en    (rresp_wr_en),
        .wr_data  (rresp_wr_data),
        .wr_full  (rresp_full),
        .rd_clk   (axi_aclk),
        .rd_rst_n (axi_aresetn),
        .rd_en    (rresp_rd_en),
        .rd_data  (rresp_rdata),
        .rd_empty (rresp_empty)
    );

    assign s_axi_bid   = bresp_err_valid ? bresp_err_id : bresp_rdata;
    assign s_axi_bresp = bresp_err_valid ? 2'b10 : 2'b00;
    assign s_axi_buser = {C_AXI_BUSER_WIDTH{1'b0}};
    assign s_axi_bvalid = bresp_err_valid || !bresp_empty;
    assign bresp_rd_en = !bresp_err_valid && s_axi_bvalid && s_axi_bready;

    // Bus layout MSB..LSB matches rresp_wr_data: SLVERR, RLAST, ARID, RDATA
    wire r_fifo_mc_slverr = rresp_rdata[C_AXI_DATA_WIDTH + C_AXI_ID_WIDTH + 1];
    wire r_fifo_rlast     = rresp_rdata[C_AXI_DATA_WIDTH + C_AXI_ID_WIDTH];

    assign s_axi_rid   = rresp_err_valid ? rresp_err_id : rresp_rdata[C_AXI_DATA_WIDTH +: C_AXI_ID_WIDTH];
    assign s_axi_rdata = rresp_err_valid ? {C_AXI_DATA_WIDTH{1'b0}} : rresp_rdata[C_AXI_DATA_WIDTH-1:0];
    assign s_axi_rresp = rresp_err_valid ? 2'b10 : (r_fifo_mc_slverr ? 2'b10 : 2'b00);
    assign s_axi_rlast = rresp_err_valid ? 1'b1 : r_fifo_rlast;
    assign s_axi_ruser = {C_AXI_RUSER_WIDTH{1'b0}};
    assign s_axi_rvalid = rresp_err_valid || !rresp_empty;
    assign rresp_rd_en = !rresp_err_valid && s_axi_rvalid && s_axi_rready;

    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            aw_hold_valid <= 1'b0;
            aw_hold_id    <= {C_AXI_ID_WIDTH{1'b0}};
            aw_hold_addr  <= {C_AXI_ADDR_WIDTH{1'b0}};
            aw_hold_ok    <= 1'b0;
            aw_hold_len   <= 8'd0;
            w_hold_valid  <= 1'b0;
            w_hold_data   <= {C_AXI_DATA_WIDTH{1'b0}};
            w_hold_strb   <= {STROBE_W{1'b0}};
            w_hold_last   <= 1'b0;
            bresp_err_valid <= 1'b0;
            bresp_err_id    <= {C_AXI_ID_WIDTH{1'b0}};
            bresp_err_pending <= 1'b0;
            bresp_err_pending_id <= {C_AXI_ID_WIDTH{1'b0}};
            rresp_err_valid <= 1'b0;
            rresp_err_id    <= {C_AXI_ID_WIDTH{1'b0}};
            rresp_err_pending <= 1'b0;
            rresp_err_pending_id <= {C_AXI_ID_WIDTH{1'b0}};
            b_legal_outstanding <= 16'd0;
            r_legal_outstanding <= 16'd0;
            write_err_active    <= 1'b0;
            write_err_wait_last <= 1'b0;
            write_err_beats_left <= 8'd0;
            write_err_id        <= {C_AXI_ID_WIDTH{1'b0}};
            w_axi_beat_idx      <= 8'd0;
        end else begin
            case ({(wreq_wr_en && w_pair_last), bresp_rd_en})
                2'b10: b_legal_outstanding <= b_legal_outstanding + 16'd1;
                2'b01: b_legal_outstanding <= b_legal_outstanding - 16'd1;
                default: ;
            endcase

            // +1+ARLEN per legal AR (beats owed); -1 per R beat completed. Same-cycle AR+R
            // must net +ARLEN (not 0), or the counter drifts and decode-error ordering breaks.
            case ({rreq_wr_en, rresp_rd_en})
                2'b10: r_legal_outstanding <= r_legal_outstanding + 16'd1 + {8'd0, s_axi_arlen};
                2'b01: r_legal_outstanding <= r_legal_outstanding - 16'd1;
                2'b11: r_legal_outstanding <= r_legal_outstanding + {8'd0, s_axi_arlen};
                default: ;
            endcase

            if (bresp_err_valid && s_axi_bready)
                bresp_err_valid <= 1'b0;
            else if (!bresp_err_valid && bresp_err_pending && (b_legal_outstanding == 16'd0)) begin
                bresp_err_valid     <= 1'b1;
                bresp_err_id        <= bresp_err_pending_id;
                bresp_err_pending   <= 1'b0;
            end

            if (rresp_err_valid && s_axi_rready)
                rresp_err_valid <= 1'b0;
            else if (!rresp_err_valid && rresp_err_pending && (r_legal_outstanding == 16'd0)) begin
                rresp_err_valid     <= 1'b1;
                rresp_err_id        <= rresp_err_pending_id;
                rresp_err_pending   <= 1'b0;
            end

            if (ar_fire && !ar_ok && !rresp_err_valid && !rresp_err_pending) begin
                if (r_legal_outstanding == 16'd0) begin
                    rresp_err_valid <= 1'b1;
                    rresp_err_id    <= s_axi_arid;
                end else begin
                    rresp_err_pending    <= 1'b1;
                    rresp_err_pending_id <= s_axi_arid;
                end
            end

            if (write_err_done) begin
                write_err_active     <= 1'b0;
                write_err_wait_last  <= 1'b0;
                write_err_beats_left <= 8'd0;
                if (b_legal_outstanding == 16'd0) begin
                    bresp_err_valid  <= 1'b1;
                    bresp_err_id     <= write_err_id;
                end else begin
                    bresp_err_pending    <= 1'b1;
                    bresp_err_pending_id <= write_err_id;
                end
            end else if (write_err_active && w_fire && !write_err_wait_last &&
                         (write_err_beats_left != 8'd0)) begin
                write_err_beats_left <= write_err_beats_left - 8'd1;
            end

            if (write_pair_error) begin
                aw_hold_valid <= 1'b0;
                w_hold_valid  <= 1'b0;
                if (!aw_pair_ok && write_pair_error_needs_drain) begin
                    write_err_active    <= 1'b1;
                    write_err_wait_last <= (aw_pair_len == 8'd0) && !w_pair_last;
                    write_err_beats_left <= (aw_pair_len != 8'd0) ? aw_pair_len : 8'd0;
                    write_err_id        <= aw_pair_id;
                end else begin
                    if (b_legal_outstanding == 16'd0) begin
                        bresp_err_valid <= 1'b1;
                        bresp_err_id    <= aw_pair_id;
                    end else begin
                        bresp_err_pending    <= 1'b1;
                        bresp_err_pending_id <= aw_pair_id;
                    end
                end
            end else begin
                if (aw_fire) begin
                    aw_hold_valid <= 1'b1;
                    aw_hold_id    <= s_axi_awid;
                    aw_hold_addr  <= s_axi_awaddr;
                    aw_hold_ok    <= aw_ok;
                    aw_hold_len   <= s_axi_awlen;
                end
                if (wreq_wr_en) begin
                    w_hold_valid <= 1'b0;
                    if (w_pair_last)
                        aw_hold_valid <= 1'b0;
                    else
                        aw_hold_addr <= aw_hold_addr + WADDR_INCR;
                    w_axi_beat_idx <= w_beat_effective + 8'd1;
                end else if (aw_fire)
                    w_axi_beat_idx <= 8'd0;
                if (w_fire && !write_err_active && !wreq_wr_en) begin
                    w_hold_valid <= 1'b1;
                    w_hold_data  <= s_axi_wdata;
                    w_hold_strb  <= s_axi_wstrb;
                    w_hold_last  <= s_axi_wlast;
                end
            end
        end
    end


endmodule
