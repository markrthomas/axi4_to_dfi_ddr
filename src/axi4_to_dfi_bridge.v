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
// Functional note: This module provides correct AXI4 handshaking, CDC, and
// legal idle DFI command encoding. DRAM command sequencing (ACT/PRE/REF),
// timing, and per-PHY phasing (DFI P0..P3) are system-specific; extend the
// dfi_* drive logic for a full controller.
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
// AXI4 -> DFI bridge (single-beat AXI4; INCR bursts with ARLEN/AWLEN == 0)
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

    // Model PHY write latency (dfi_clk cycles) before BVALID in AXI domain
    parameter integer DFI_WRITE_ACK_CYCLES = 4,
    // Model PHY read latency before RVALID
    parameter integer DFI_READ_DATA_CYCLES = 6
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
    assign dfi_init_start   = 1'b0; // Stub: drive real MC init sequence if needed

    //-------------------------------------------------------------------------
    // FIFO payloads (packed)
    //-------------------------------------------------------------------------
    localparam integer WREQ_W = 1 + C_AXI_ID_WIDTH + C_AXI_ADDR_WIDTH + C_AXI_DATA_WIDTH + STROBE_W;
    // op[0]=0 write request: id, addr, data, strb

    localparam integer RREQ_W = C_AXI_ID_WIDTH + C_AXI_ADDR_WIDTH;

    localparam integer BRESP_FIFO_W = C_AXI_ID_WIDTH;
    localparam integer RRESP_FIFO_W = C_AXI_ID_WIDTH + C_AXI_DATA_WIDTH;

    //-------------------------------------------------------------------------
    // AXI: accept only AXI4 INCR, single beat (len==0), full-width transfers
    //-------------------------------------------------------------------------
    wire aw_ok = (s_axi_awburst == 2'b01) && (s_axi_awlen == 8'd0) &&
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
    reg w_hold_valid;
    reg [C_AXI_DATA_WIDTH-1:0] w_hold_data;
    reg [STROBE_W-1:0] w_hold_strb;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid && s_axi_wready;

    wire aw_pair_valid = aw_hold_valid || aw_fire;
    wire w_pair_valid  = w_hold_valid || w_fire;

    wire [C_AXI_ID_WIDTH-1:0] aw_pair_id =
        aw_hold_valid ? aw_hold_id : s_axi_awid;
    wire [C_AXI_ADDR_WIDTH-1:0] aw_pair_addr =
        aw_hold_valid ? aw_hold_addr : s_axi_awaddr;
    wire [C_AXI_DATA_WIDTH-1:0] w_pair_data =
        w_hold_valid ? w_hold_data : s_axi_wdata;
    wire [STROBE_W-1:0] w_pair_strb =
        w_hold_valid ? w_hold_strb : s_axi_wstrb;

    wire wreq_wr_en = aw_pair_valid && w_pair_valid && !wreq_full;
    wire [WREQ_W-1:0] wreq_push_vec = {1'b0, aw_pair_id, aw_pair_addr, w_pair_data, w_pair_strb};

    assign s_axi_awready = !aw_hold_valid && aw_ok;
    assign s_axi_wready  = !w_hold_valid && s_axi_wlast;
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

    wire rreq_wr_en = s_axi_arvalid && s_axi_arready;
    wire [RREQ_W-1:0] rreq_push = {s_axi_arid, s_axi_araddr};

    assign s_axi_arready = ar_ok && !rreq_full;

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
    // DFI clock domain: single driver for dfi_*; writes preferred over reads
    //-------------------------------------------------------------------------
    localparam integer TIMER_W = 8;

    reg wreq_rd_en_r;
    reg rreq_rd_en_r;
    // Latch FIFO output on pop cycle; rd_data advances after rd_en so _r cycle must
    // use this snapshot (FWFT output follows rptr and shows 0 when empty after pop).
    reg [WREQ_W-1:0] wreq_snapshot;
    reg [RREQ_W-1:0] rreq_snapshot;

    reg w_busy;
    reg [TIMER_W-1:0] w_timer;
    reg [C_AXI_ID_WIDTH-1:0] w_pending_id;

    reg r_busy;
    reg [TIMER_W-1:0] r_timer;
    reg [C_AXI_ID_WIDTH-1:0] r_pending_id;
    reg [C_AXI_DATA_WIDTH-1:0] r_capture;

    wire [C_AXI_ID_WIDTH-1:0] wreq_id =
        wreq_snapshot[STROBE_W+C_AXI_DATA_WIDTH+C_AXI_ADDR_WIDTH +: C_AXI_ID_WIDTH];
    wire [C_AXI_ID_WIDTH-1:0] rreq_id = rreq_snapshot[C_AXI_ADDR_WIDTH +: C_AXI_ID_WIDTH];

    wire dfi_mc_ready = dfi_init_complete;

    assign wreq_rd_en = dfi_mc_ready && !w_busy && !r_busy && !wreq_rd_en_r &&
                        !wreq_empty && !bresp_full;
    assign rreq_rd_en = dfi_mc_ready && !w_busy && !r_busy && !rreq_rd_en_r &&
                        wreq_empty && !rreq_empty && !rresp_full;

    wire bresp_full;
    wire rresp_full;

    wire bresp_wr_en = w_busy && (w_timer == 1) && !bresp_full;
    wire [BRESP_FIFO_W-1:0] bresp_wr_data = w_pending_id;

    wire rresp_wr_en = r_busy && (r_timer == 1) && !rresp_full;
    wire [RRESP_FIFO_W-1:0] rresp_wr_data = {r_pending_id, r_capture};

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

    assign s_axi_bid   = bresp_rdata;
    assign s_axi_bresp = 2'b00;
    assign s_axi_buser = {C_AXI_BUSER_WIDTH{1'b0}};
    assign s_axi_bvalid = !bresp_empty;
    assign bresp_rd_en = s_axi_bvalid && s_axi_bready;

    assign s_axi_rid   = rresp_rdata[C_AXI_DATA_WIDTH +: C_AXI_ID_WIDTH];
    assign s_axi_rdata = rresp_rdata[C_AXI_DATA_WIDTH-1:0];
    assign s_axi_rresp = 2'b00;
    assign s_axi_rlast = 1'b1;
    assign s_axi_ruser = {C_AXI_RUSER_WIDTH{1'b0}};
    assign s_axi_rvalid = !rresp_empty;
    assign rresp_rd_en = s_axi_rvalid && s_axi_rready;

    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            aw_hold_valid <= 1'b0;
            aw_hold_id    <= {C_AXI_ID_WIDTH{1'b0}};
            aw_hold_addr  <= {C_AXI_ADDR_WIDTH{1'b0}};
            w_hold_valid  <= 1'b0;
            w_hold_data   <= {C_AXI_DATA_WIDTH{1'b0}};
            w_hold_strb   <= {STROBE_W{1'b0}};
        end else begin
            if (wreq_wr_en) begin
                aw_hold_valid <= 1'b0;
                w_hold_valid  <= 1'b0;
            end else begin
                if (aw_fire) begin
                    aw_hold_valid <= 1'b1;
                    aw_hold_id    <= s_axi_awid;
                    aw_hold_addr  <= s_axi_awaddr;
                end
                if (w_fire) begin
                    w_hold_valid <= 1'b1;
                    w_hold_data  <= s_axi_wdata;
                    w_hold_strb  <= s_axi_wstrb;
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
            w_busy           <= 1'b0;
            w_timer          <= {TIMER_W{1'b0}};
            w_pending_id     <= {C_AXI_ID_WIDTH{1'b0}};
            r_busy           <= 1'b0;
            r_timer          <= {TIMER_W{1'b0}};
            r_pending_id     <= {C_AXI_ID_WIDTH{1'b0}};
            r_capture        <= {C_AXI_DATA_WIDTH{1'b0}};
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
            dfi_wrdata_en <= 1'b0;
            dfi_rddata_en <= 1'b0;

            if (w_busy) begin
                if ((w_timer == 1) && !bresp_full)
                    w_busy <= 1'b0;
                else if (w_timer != 1)
                    w_timer <= w_timer - 1'b1;
            end else if (r_busy) begin
                if (dfi_rddata_valid)
                    r_capture <= dfi_rddata[C_AXI_DATA_WIDTH-1:0];
                if ((r_timer == 1) && !rresp_full)
                    r_busy <= 1'b0;
                else if (r_timer != 1)
                    r_timer <= r_timer - 1'b1;
            end else if (wreq_rd_en_r) begin
                dfi_address <= wreq_snapshot[C_AXI_ADDR_WIDTH-1:0];
                if (DFI_BANK_WIDTH > 0)
                    dfi_bank <= wreq_snapshot[2 +: DFI_BANK_WIDTH];
                dfi_wrdata <= wreq_snapshot[C_AXI_DATA_WIDTH+STROBE_W-1:STROBE_W];
                dfi_wrdata_mask <= ~wreq_snapshot[STROBE_W-1:0];
                dfi_cas_n     <= 1'b0;
                dfi_we_n      <= 1'b0;
                dfi_cs_n      <= {DFI_CS_WIDTH{1'b0}};
                dfi_wrdata_en <= 1'b1;
                w_pending_id  <= wreq_id;
                w_busy        <= 1'b1;
                w_timer       <= DFI_WRITE_ACK_CYCLES[TIMER_W-1:0];
            end else if (rreq_rd_en_r) begin
                dfi_address <= rreq_snapshot[C_AXI_ADDR_WIDTH-1:0];
                if (DFI_BANK_WIDTH > 0)
                    dfi_bank <= rreq_snapshot[2 +: DFI_BANK_WIDTH];
                dfi_cas_n     <= 1'b0;
                dfi_we_n      <= 1'b1;
                dfi_cs_n      <= {DFI_CS_WIDTH{1'b0}};
                dfi_rddata_en <= 1'b1;
                r_pending_id  <= rreq_id;
                r_capture       <= {C_AXI_DATA_WIDTH{1'b0}};
                r_busy          <= 1'b1;
                r_timer         <= DFI_READ_DATA_CYCLES[TIMER_W-1:0];
            end
        end
    end

endmodule
