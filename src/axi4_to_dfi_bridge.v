//=============================================================================
// axi4_to_dfi_bridge.v
//
// AXI4 slave (AMBA AXI4, ARM IHI0022) to DFI memory-controller/PHY signals
// (JEDEC DFI 4.0 command + write/read data plane; compatible subset with
//  DFI 5.x which keeps the same dfi_* naming for this path).
//
// Tooling: Icarus Verilog (iverilog) - compile with: iverilog -g2001 src/axi4_to_dfi_bridge.v
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
// parameterized tRP, tRCD, and MC_CL. Refresh and multi-clock DFI phase buses
// (P0–P3) are not implemented. dfi_act_n is low only during ACT; optional
// dfi_init_start pulse after reset uses DFI_INIT_START_CYCLES (default 0).
//=============================================================================

`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Two-flop synchronizer (vector)
//-----------------------------------------------------------------------------
module cdc_sync #(
    parameter integer WIDTH = 1
) (
    input  wire              dst_clk,
    input  wire              dst_rst_n,
    input  wire [WIDTH-1:0]  d,
    output reg  [WIDTH-1:0]  q
);
    reg [WIDTH-1:0] s1;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            s1 <= {WIDTH{1'b0}};
            q  <= {WIDTH{1'b0}};
        end else begin
            s1 <= d;
            q  <= s1;
        end
    end
endmodule

//-----------------------------------------------------------------------------
// Gray-code async FIFO (Cliff Cummings style; power-of-2 DEPTH)
//-----------------------------------------------------------------------------
module async_fifo_gray #(
    parameter integer WIDTH  = 8,
    parameter integer DEPTH  = 8,
    parameter integer PTRW   = $clog2(DEPTH) + 1
) (
    input  wire              wr_clk,
    input  wire              wr_rst_n,
    input  wire              wr_en,
    input  wire [WIDTH-1:0]  wr_data,
    output wire              wr_full,

    input  wire              rd_clk,
    input  wire              rd_rst_n,
    input  wire              rd_en,
    output wire [WIDTH-1:0]  rd_data,
    output wire              rd_empty
);
    function [PTRW-1:0] bin2gray;
        input [PTRW-1:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    localparam integer AW = $clog2(DEPTH);

    initial begin
        if (DEPTH < 2) begin
            $display("ERROR: async_fifo_gray DEPTH=%0d must be >= 2", DEPTH);
            $finish(1);
        end
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $display("ERROR: async_fifo_gray DEPTH=%0d must be a power of two", DEPTH);
            $finish(1);
        end
        if (WIDTH < 1) begin
            $display("ERROR: async_fifo_gray WIDTH=%0d must be >= 1", WIDTH);
            $finish(1);
        end
    end

    reg [WIDTH-1:0] mem [0:DEPTH-1];

    reg [PTRW-1:0] wptr_bin, wptr_gray, rptr_bin, rptr_gray;
    wire [PTRW-1:0] wptr_gray_rd;
    wire [PTRW-1:0] rptr_gray_wr;

    wire [PTRW-1:0] wptr_gray_next = bin2gray(wptr_bin + 1'b1);
    wire [PTRW-1:0] rptr_gray_next = bin2gray(rptr_bin + 1'b1);

    wire [PTRW-1:0] wptr_full_cmp =
        (PTRW > 2) ? {~rptr_gray_wr[PTRW-1:PTRW-2], rptr_gray_wr[PTRW-3:0]} :
                     {~rptr_gray_wr[PTRW-1:PTRW-2]};
    wire full_int = (wptr_gray_next == wptr_full_cmp);
    assign wr_full = full_int;

    wire empty_int = (wptr_gray_rd == rptr_gray);
    assign rd_empty = empty_int;

    // First-word fall-through: data valid whenever !empty (matches AXI-style valid/data).
    assign rd_data = empty_int ? {WIDTH{1'b0}} : mem[rptr_bin[AW-1:0]];

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wptr_bin  <= {PTRW{1'b0}};
            wptr_gray <= {PTRW{1'b0}};
        end else if (wr_en && !full_int) begin
            mem[wptr_bin[AW-1:0]] <= wr_data;
            wptr_bin  <= wptr_bin + 1'b1;
            wptr_gray <= wptr_gray_next;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rptr_bin  <= {PTRW{1'b0}};
            rptr_gray <= {PTRW{1'b0}};
        end else begin
            if (rd_en && !empty_int) begin
                rptr_bin  <= rptr_bin + 1'b1;
                rptr_gray <= rptr_gray_next;
            end
        end
    end

    cdc_sync #(.WIDTH(PTRW)) u_sync_w2r (
        .dst_clk  (rd_clk),
        .dst_rst_n(rd_rst_n),
        .d        (wptr_gray),
        .q        (wptr_gray_rd)
    );

    cdc_sync #(.WIDTH(PTRW)) u_sync_r2w (
        .dst_clk  (wr_clk),
        .dst_rst_n(wr_rst_n),
        .d        (rptr_gray),
        .q        (rptr_gray_wr)
    );
endmodule

//-----------------------------------------------------------------------------
// AXI4 -> DFI bridge (INCR write bursts up to C_MAX_WRITE_AWLEN; reads single-beat)
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
    parameter integer MC_CL        = 6,  // CAS to first read data (PHY should align)
    parameter integer MC_RD_DV_MAX = 16,  // cycles to wait for dfi_rddata_valid after CL

    // DFI sideband: pulse dfi_init_start for this many dfi_clk cycles after reset release (0 = tie off)
    parameter integer DFI_INIT_START_CYCLES = 0,

    // AXI write: max AWLEN for legal INCR bursts (0 = single-beat only; default 3 = up to 4 beats)
    parameter integer C_MAX_WRITE_AWLEN = 3
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
    output reg  [DFI_ADDR_WIDTH-1:0]     dfi_address,
    output reg  [DFI_BANK_WIDTH-1:0]     dfi_bank,
    output reg                           dfi_ras_n,
    output reg                           dfi_cas_n,
    output reg                           dfi_we_n,
    output reg  [DFI_CS_WIDTH-1:0]       dfi_cs_n,
    output reg  [DFI_ODT_WIDTH-1:0]      dfi_odt,
    output reg  [DFI_CKE_WIDTH-1:0]      dfi_cke,
    output reg                           dfi_act_n,

    // Write data path
    output reg  [DFI_DATA_WIDTH-1:0]     dfi_wrdata,
    output reg  [DFI_MASK_WIDTH-1:0]     dfi_wrdata_mask,
    output reg                           dfi_wrdata_en,

    // Read data path
    input  wire [DFI_DATA_WIDTH-1:0]     dfi_rddata,
    input  wire                          dfi_rddata_valid,
    output reg                           dfi_rddata_en
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

    localparam integer RREQ_W = C_AXI_ID_WIDTH + C_AXI_ADDR_WIDTH;

    localparam integer BRESP_FIFO_W = C_AXI_ID_WIDTH;
    // MSB: 1 = SLVERR (no dfi_rddata_valid within MC_RD_DV_MAX); then ARID; then RDATA
    localparam integer RRESP_FIFO_W = 1 + C_AXI_ID_WIDTH + C_AXI_DATA_WIDTH;

    localparam [C_AXI_ADDR_WIDTH-1:0] WADDR_INCR = C_AXI_DATA_WIDTH / 8;

    //-------------------------------------------------------------------------
    // AXI: INCR writes up to C_MAX_WRITE_AWLEN; reads single-beat only; full-width size
    //-------------------------------------------------------------------------
    wire aw_ok = (s_axi_awburst == 2'b01) && (s_axi_awlen <= C_MAX_WRITE_AWLEN) &&
                 (s_axi_awsize == $clog2(C_AXI_DATA_WIDTH/8));
    wire ar_ok = (s_axi_arburst == 2'b01) && (s_axi_arlen == 8'd0) &&
                 (s_axi_arsize == $clog2(C_AXI_DATA_WIDTH/8));

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
    reg rresp_err_valid;
    reg [C_AXI_ID_WIDTH-1:0] rresp_err_id;

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

    assign s_axi_awready = !aw_hold_valid && !write_err_active && !bresp_err_valid;
    assign s_axi_wready  = !w_hold_valid && !bresp_err_valid;
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
    wire [RREQ_W-1:0] rreq_push = {s_axi_arid, s_axi_araddr};

    assign s_axi_arready = ar_ok ? !rreq_full : !rresp_err_valid;

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
    // DFI clock domain: SDRAM-style scheduler (PRE/ACT/CAS, open-page per bank)
    //-------------------------------------------------------------------------
    localparam integer NBANKS = (1 << DFI_BANK_WIDTH);

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
        if (MC_T_RP < 0 || MC_T_RCD < 0 || MC_CL < 0 || MC_RD_DV_MAX < 0 || DFI_WRITE_ACK_CYCLES < 0) begin
            $display("ERROR: axi4_to_dfi_bridge: MC timing and DFI_WRITE_ACK_CYCLES must be >= 0");
            $finish(1);
        end
        if (C_MAX_WRITE_AWLEN < 0 || C_MAX_WRITE_AWLEN > 255) begin
            $display("ERROR: axi4_to_dfi_bridge: C_MAX_WRITE_AWLEN (%0d) must be in 0..255", C_MAX_WRITE_AWLEN);
            $finish(1);
        end
    end

    localparam [3:0] ST_IDLE      = 4'd0;
    localparam [3:0] ST_PRE_CMD  = 4'd1;
    localparam [3:0] ST_WAIT_RP  = 4'd2;
    localparam [3:0] ST_ACT_CMD  = 4'd3;
    localparam [3:0] ST_WAIT_RCD = 4'd4;
    localparam [3:0] ST_WR_CMD   = 4'd5;
    localparam [3:0] ST_WAIT_B   = 4'd6;
    localparam [3:0] ST_RD_CMD   = 4'd7;
    localparam [3:0] ST_WAIT_CL  = 4'd8;
    localparam [3:0] ST_WAIT_DV  = 4'd9;
    localparam [3:0] ST_PULSE_R  = 4'd10;

    reg wreq_rd_en_r;
    reg rreq_rd_en_r;
    reg [WREQ_W-1:0] wreq_snapshot;
    reg [RREQ_W-1:0] rreq_snapshot;

    reg  [3:0]               mc_state;
    reg  [7:0]               mc_ctr;
    reg  [3:0]               mc_after_rp;
    reg  [3:0]               mc_after_rcd;
    reg                      mc_is_wr;
    reg  [C_AXI_ID_WIDTH-1:0] mc_id;
    reg  [C_AXI_ADDR_WIDTH-1:0] mc_addr;
    reg  [C_AXI_DATA_WIDTH-1:0] mc_wdata;
    reg  [STROBE_W-1:0]      mc_wstrb;
    reg  [DFI_BANK_WIDTH-1:0] mc_bank;
    reg  [MC_ROW_BITS-1:0]   mc_row;
    reg  [MC_COL_BITS-1:0]   mc_col;
    reg                      mc_wr_last_beat;
    reg  [NBANKS-1:0]        row_open_mask;
    reg  [MC_ROW_BITS-1:0]   open_row_mem [0:NBANKS-1];
    reg  [C_AXI_DATA_WIDTH-1:0] r_capture;
    reg                      mc_got_rddata;
    integer                  open_row_rst_i;

    wire [C_AXI_ADDR_WIDTH-1:0] wreq_addr =
        wreq_snapshot[STROBE_W+C_AXI_DATA_WIDTH +: C_AXI_ADDR_WIDTH];
    wire [C_AXI_ID_WIDTH-1:0] wreq_id =
        wreq_snapshot[STROBE_W+C_AXI_DATA_WIDTH+C_AXI_ADDR_WIDTH +: C_AXI_ID_WIDTH];
    wire [C_AXI_ID_WIDTH-1:0] rreq_id = rreq_snapshot[C_AXI_ADDR_WIDTH +: C_AXI_ID_WIDTH];

    wire [0:0] dfi_init_complete_sync;
    wire dfi_mc_ready = dfi_init_complete_sync[0];

    cdc_sync #(.WIDTH(1)) u_sync_dfi_init_complete (
        .dst_clk  (dfi_clk),
        .dst_rst_n(dfi_rst_n),
        .d        ({dfi_init_complete}),
        .q        (dfi_init_complete_sync)
    );

    wire mc_idle = (mc_state == ST_IDLE);

    assign wreq_rd_en = dfi_mc_ready && mc_idle && !wreq_rd_en_r &&
                        !rreq_rd_en_r && !wreq_empty && !bresp_full;
    assign rreq_rd_en = dfi_mc_ready && mc_idle && !wreq_rd_en_r &&
                        !rreq_rd_en_r && wreq_empty && !rreq_empty && !rresp_full;

    wire bresp_full;
    wire rresp_full;

    wire bresp_wr_en = (mc_state == ST_WAIT_B) && (mc_ctr == 8'd1) && !bresp_full &&
                       mc_wr_last_beat;
    wire [BRESP_FIFO_W-1:0] bresp_wr_data = mc_id;

    wire rresp_wr_en = (mc_state == ST_PULSE_R) && !rresp_full;
    wire [RRESP_FIFO_W-1:0] rresp_wr_data = {!mc_got_rddata, mc_id, r_capture};

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

    wire r_fifo_mc_slverr = rresp_rdata[C_AXI_DATA_WIDTH + C_AXI_ID_WIDTH];

    assign s_axi_rid   = rresp_err_valid ? rresp_err_id : rresp_rdata[C_AXI_DATA_WIDTH +: C_AXI_ID_WIDTH];
    assign s_axi_rdata = rresp_err_valid ? {C_AXI_DATA_WIDTH{1'b0}} : rresp_rdata[C_AXI_DATA_WIDTH-1:0];
    assign s_axi_rresp = rresp_err_valid ? 2'b10 : (r_fifo_mc_slverr ? 2'b10 : 2'b00);
    assign s_axi_rlast = 1'b1;
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
            rresp_err_valid <= 1'b0;
            rresp_err_id    <= {C_AXI_ID_WIDTH{1'b0}};
            write_err_active    <= 1'b0;
            write_err_wait_last <= 1'b0;
            write_err_beats_left <= 8'd0;
            write_err_id        <= {C_AXI_ID_WIDTH{1'b0}};
            w_axi_beat_idx      <= 8'd0;
        end else begin
            if (bresp_err_valid && s_axi_bready)
                bresp_err_valid <= 1'b0;

            if (rresp_err_valid && s_axi_rready)
                rresp_err_valid <= 1'b0;

            if (ar_fire && !ar_ok && !rresp_err_valid) begin
                rresp_err_valid <= 1'b1;
                rresp_err_id    <= s_axi_arid;
            end

            if (write_err_done) begin
                write_err_active     <= 1'b0;
                write_err_wait_last  <= 1'b0;
                write_err_beats_left <= 8'd0;
                bresp_err_valid      <= 1'b1;
                bresp_err_id         <= write_err_id;
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
                    bresp_err_valid <= 1'b1;
                    bresp_err_id    <= aw_pair_id;
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

    always @(posedge dfi_clk or negedge dfi_rst_n) begin
        if (!dfi_rst_n) begin
            dfi_address      <= {DFI_ADDR_WIDTH{1'b0}};
            dfi_bank         <= {DFI_BANK_WIDTH{1'b0}};
            dfi_ras_n        <= 1'b1;
            dfi_cas_n        <= 1'b1;
            dfi_we_n         <= 1'b1;
            dfi_cs_n         <= {DFI_CS_WIDTH{1'b1}};
            dfi_odt          <= {DFI_ODT_WIDTH{1'b0}};
            dfi_cke          <= {DFI_CKE_WIDTH{1'b1}};
            dfi_act_n        <= 1'b1;
            dfi_wrdata       <= {DFI_DATA_WIDTH{1'b0}};
            dfi_wrdata_mask  <= {DFI_MASK_WIDTH{1'b0}};
            dfi_wrdata_en    <= 1'b0;
            dfi_rddata_en    <= 1'b0;
            wreq_rd_en_r     <= 1'b0;
            rreq_rd_en_r     <= 1'b0;
            wreq_snapshot    <= {WREQ_W{1'b0}};
            rreq_snapshot    <= {RREQ_W{1'b0}};
            mc_state         <= ST_IDLE;
            mc_ctr           <= 8'd0;
            mc_after_rp      <= ST_IDLE;
            mc_after_rcd     <= ST_IDLE;
            mc_is_wr         <= 1'b0;
            mc_id            <= {C_AXI_ID_WIDTH{1'b0}};
            mc_addr          <= {C_AXI_ADDR_WIDTH{1'b0}};
            mc_wdata         <= {C_AXI_DATA_WIDTH{1'b0}};
            mc_wstrb         <= {STROBE_W{1'b0}};
            mc_bank          <= {DFI_BANK_WIDTH{1'b0}};
            mc_row           <= {MC_ROW_BITS{1'b0}};
            mc_col           <= {MC_COL_BITS{1'b0}};
            mc_wr_last_beat  <= 1'b0;
            row_open_mask    <= {NBANKS{1'b0}};
            r_capture        <= {C_AXI_DATA_WIDTH{1'b0}};
            mc_got_rddata    <= 1'b0;
            for (open_row_rst_i = 0; open_row_rst_i < NBANKS; open_row_rst_i = open_row_rst_i + 1)
                open_row_mem[open_row_rst_i] <= {MC_ROW_BITS{1'b0}};
        end else begin
            if (wreq_rd_en)
                wreq_snapshot <= wreq_rdata;
            if (rreq_rd_en)
                rreq_snapshot <= rreq_rdata;
            wreq_rd_en_r <= wreq_rd_en;
            rreq_rd_en_r <= rreq_rd_en;

            dfi_ras_n     <= 1'b1;
            dfi_cas_n     <= 1'b1;
            dfi_we_n      <= 1'b1;
            dfi_cs_n      <= {DFI_CS_WIDTH{1'b1}};
            dfi_act_n     <= 1'b1;
            dfi_wrdata_en <= 1'b0;
            dfi_rddata_en <= 1'b0;

            case (mc_state)
                ST_IDLE: begin
                    if (wreq_rd_en_r) begin
                        mc_is_wr <= 1'b1;
                        mc_wr_last_beat <= wreq_snapshot[WREQ_W-1];
                        mc_id    <= wreq_id;
                        mc_addr  <= wreq_addr;
                        mc_wdata <= wreq_snapshot[C_AXI_DATA_WIDTH+STROBE_W-1:STROBE_W];
                        mc_wstrb <= wreq_snapshot[STROBE_W-1:0];
                        mc_bank  <= wreq_addr[MC_COL_BITS+MC_ROW_BITS +: DFI_BANK_WIDTH];
                        mc_row   <= wreq_addr[MC_COL_BITS +: MC_ROW_BITS];
                        mc_col   <= wreq_addr[MC_COL_BITS-1:0];
                        if (!row_open_mask[wreq_addr[MC_COL_BITS+MC_ROW_BITS +: DFI_BANK_WIDTH]]) begin
                            mc_after_rcd <= ST_WR_CMD;
                            mc_state     <= ST_ACT_CMD;
                        end else if (open_row_mem[wreq_addr[MC_COL_BITS+MC_ROW_BITS +: DFI_BANK_WIDTH]] !=
                                     wreq_addr[MC_COL_BITS +: MC_ROW_BITS]) begin
                            mc_after_rp  <= ST_ACT_CMD;
                            mc_after_rcd <= ST_WR_CMD;
                            mc_state     <= ST_PRE_CMD;
                        end else
                            mc_state <= ST_WR_CMD;
                    end else if (rreq_rd_en_r) begin
                        mc_is_wr <= 1'b0;
                        mc_id    <= rreq_id;
                        mc_addr  <= rreq_snapshot[C_AXI_ADDR_WIDTH-1:0];
                        mc_bank  <= rreq_snapshot[MC_COL_BITS+MC_ROW_BITS +: DFI_BANK_WIDTH];
                        mc_row   <= rreq_snapshot[MC_COL_BITS +: MC_ROW_BITS];
                        mc_col   <= rreq_snapshot[MC_COL_BITS-1:0];
                        if (!row_open_mask[rreq_snapshot[MC_COL_BITS+MC_ROW_BITS +: DFI_BANK_WIDTH]]) begin
                            mc_after_rcd <= ST_RD_CMD;
                            mc_state     <= ST_ACT_CMD;
                        end else if (open_row_mem[rreq_snapshot[MC_COL_BITS+MC_ROW_BITS +: DFI_BANK_WIDTH]] !=
                                     rreq_snapshot[MC_COL_BITS +: MC_ROW_BITS]) begin
                            mc_after_rp  <= ST_ACT_CMD;
                            mc_after_rcd <= ST_RD_CMD;
                            mc_state     <= ST_PRE_CMD;
                        end else
                            mc_state <= ST_RD_CMD;
                    end
                end
                ST_PRE_CMD: begin
                    dfi_bank    <= mc_bank;
                    dfi_address <= open_row_mem[mc_bank];
                    dfi_ras_n   <= 1'b0;
                    dfi_cas_n   <= 1'b1;
                    dfi_we_n    <= 1'b0;
                    dfi_cs_n    <= {DFI_CS_WIDTH{1'b0}};
                    row_open_mask[mc_bank] <= 1'b0;
                    if (MC_T_RP == 0)
                        mc_state <= mc_after_rp;
                    else begin
                        mc_ctr   <= MC_T_RP[7:0];
                        mc_state <= ST_WAIT_RP;
                    end
                end
                ST_WAIT_RP: begin
                    if (mc_ctr == 8'd1)
                        mc_state <= mc_after_rp;
                    else
                        mc_ctr <= mc_ctr - 8'd1;
                end
                ST_ACT_CMD: begin
                    dfi_bank    <= mc_bank;
                    dfi_address <= mc_row;
                    dfi_act_n   <= 1'b0;
                    dfi_ras_n   <= 1'b0;
                    dfi_cas_n   <= 1'b1;
                    dfi_we_n    <= 1'b1;
                    dfi_cs_n    <= {DFI_CS_WIDTH{1'b0}};
                    if (MC_T_RCD == 0) begin
                        row_open_mask[mc_bank] <= 1'b1;
                        open_row_mem[mc_bank]    <= mc_row;
                        mc_state                 <= mc_after_rcd;
                    end else begin
                        mc_ctr   <= MC_T_RCD[7:0];
                        mc_state <= ST_WAIT_RCD;
                    end
                end
                ST_WAIT_RCD: begin
                    if (mc_ctr == 8'd1) begin
                        row_open_mask[mc_bank] <= 1'b1;
                        open_row_mem[mc_bank]    <= mc_row;
                        mc_state                 <= mc_after_rcd;
                    end else
                        mc_ctr <= mc_ctr - 8'd1;
                end
                ST_WR_CMD: begin
                    dfi_bank          <= mc_bank;
                    dfi_address       <= mc_col;
                    dfi_ras_n         <= 1'b1;
                    dfi_cas_n         <= 1'b0;
                    dfi_we_n          <= 1'b0;
                    dfi_cs_n          <= {DFI_CS_WIDTH{1'b0}};
                    dfi_wrdata        <= mc_wdata;
                    dfi_wrdata_mask   <= ~mc_wstrb;
                    dfi_wrdata_en     <= 1'b1;
                    if (DFI_WRITE_ACK_CYCLES == 0) begin
                        if (mc_wr_last_beat) begin
                            if (!bresp_full)
                                mc_state <= ST_IDLE;
                        end else
                            mc_state <= ST_IDLE;
                    end else begin
                        mc_ctr   <= DFI_WRITE_ACK_CYCLES[7:0];
                        mc_state <= ST_WAIT_B;
                    end
                end
                ST_WAIT_B: begin
                    if (mc_ctr == 8'd1) begin
                        if (mc_wr_last_beat) begin
                            if (!bresp_full)
                                mc_state <= ST_IDLE;
                        end else
                            mc_state <= ST_IDLE;
                    end else
                        mc_ctr <= mc_ctr - 8'd1;
                end
                ST_RD_CMD: begin
                    dfi_bank      <= mc_bank;
                    dfi_address   <= mc_col;
                    dfi_ras_n     <= 1'b1;
                    dfi_cas_n     <= 1'b0;
                    dfi_we_n      <= 1'b1;
                    dfi_cs_n      <= {DFI_CS_WIDTH{1'b0}};
                    dfi_rddata_en <= 1'b1;
                    r_capture     <= {C_AXI_DATA_WIDTH{1'b0}};
                    mc_got_rddata <= 1'b0;
                    if (MC_CL == 0) begin
                        mc_ctr   <= MC_RD_DV_MAX[7:0];
                        mc_state <= ST_WAIT_DV;
                    end else begin
                        mc_ctr   <= MC_CL[7:0];
                        mc_state <= ST_WAIT_CL;
                    end
                end
                ST_WAIT_CL: begin
                    if (mc_ctr == 8'd1) begin
                        mc_ctr   <= MC_RD_DV_MAX[7:0];
                        mc_state <= ST_WAIT_DV;
                    end else
                        mc_ctr <= mc_ctr - 8'd1;
                end
                ST_WAIT_DV: begin
                    if (dfi_rddata_valid) begin
                        r_capture     <= dfi_rddata[C_AXI_DATA_WIDTH-1:0];
                        mc_got_rddata <= 1'b1;
                    end
                    if (dfi_rddata_valid || (mc_ctr == 8'd0))
                        mc_state <= ST_PULSE_R;
                    else
                        mc_ctr <= mc_ctr - 8'd1;
                end
                ST_PULSE_R: begin
                    if (!rresp_full)
                        mc_state <= ST_IDLE;
                end
                default: mc_state <= ST_IDLE;
            endcase
        end
    end

endmodule
