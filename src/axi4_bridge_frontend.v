// axi4_bridge_frontend.v — AXI4 slave decode, AW/W/AR pairing, CDC FIFOs (wreq/rreq/bresp/rresp),
//  and B/R channel ordering vs local SLVERR (axi_aclk domain + async_fifo_gray to dfi_clk).
`timescale 1ns / 1ps

module axi4_bridge_frontend #(
    parameter integer C_AXI_ADDR_WIDTH = 32,
    parameter integer C_AXI_DATA_WIDTH = 64,
    parameter integer C_AXI_ID_WIDTH   = 4,
    parameter integer C_AXI_AWUSER_WIDTH = 1,
    parameter integer C_AXI_WUSER_WIDTH  = 1,
    parameter integer C_AXI_BUSER_WIDTH  = 1,
    parameter integer C_AXI_ARUSER_WIDTH = 1,
    parameter integer C_AXI_RUSER_WIDTH  = 1,

    parameter integer CDC_FIFO_DEPTH = 8,

    parameter integer MC_COL_BITS  = 10,
    parameter integer MC_ROW_BITS  = 14,
    parameter integer DFI_BANK_WIDTH = 3,

    parameter integer C_MAX_WRITE_AWLEN = 3,
    parameter integer C_MAX_READ_ARLEN = 3,

    parameter integer WREQ_W        = 1 + C_AXI_ID_WIDTH + C_AXI_ADDR_WIDTH +
                                      C_AXI_DATA_WIDTH + (C_AXI_DATA_WIDTH / 8),
    parameter integer RREQ_W        = 8 + C_AXI_ID_WIDTH + C_AXI_ADDR_WIDTH,
    parameter integer BRESP_FIFO_W  = C_AXI_ID_WIDTH,
    parameter integer RRESP_FIFO_W  = 1 + 1 + C_AXI_ID_WIDTH + C_AXI_DATA_WIDTH
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

    output wire [WREQ_W-1:0]             mc_wreq_rdata,
    output wire                          mc_wreq_empty,
    input  wire                          mc_wreq_rd_en,

    output wire [RREQ_W-1:0]             mc_rreq_rdata,
    output wire                          mc_rreq_empty,
    input  wire                          mc_rreq_rd_en,

    output wire                          mc_bresp_full,
    input  wire                          mc_bresp_wr_en,
    input  wire [BRESP_FIFO_W-1:0]       mc_bresp_wr_data,

    output wire                          mc_rresp_full,
    input  wire                          mc_rresp_wr_en,
    input  wire [RRESP_FIFO_W-1:0]       mc_rresp_wr_data
);

    localparam integer STROBE_W = C_AXI_DATA_WIDTH / 8;
    localparam [C_AXI_ADDR_WIDTH-1:0] WADDR_INCR = C_AXI_DATA_WIDTH / 8;

    wire aw_ok = (s_axi_awburst == 2'b01) && (s_axi_awlen <= C_MAX_WRITE_AWLEN) &&
                 (s_axi_awsize == $clog2(C_AXI_DATA_WIDTH/8));
    wire ar_ok_basic = (s_axi_arburst == 2'b01) && (s_axi_arlen <= C_MAX_READ_ARLEN) &&
                       (s_axi_arsize == $clog2(C_AXI_DATA_WIDTH/8));
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
        .wr_en    (mc_bresp_wr_en),
        .wr_data  (mc_bresp_wr_data),
        .wr_full  (mc_bresp_full),
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
        .wr_en    (mc_rresp_wr_en),
        .wr_data  (mc_rresp_wr_data),
        .wr_full  (mc_rresp_full),
        .rd_clk   (axi_aclk),
        .rd_rst_n (axi_aresetn),
        .rd_en    (rresp_rd_en),
        .rd_data  (rresp_rdata),
        .rd_empty (rresp_empty)
    );

    assign mc_wreq_rdata = wreq_rdata;
    assign mc_wreq_empty = wreq_empty;
    assign wreq_rd_en    = mc_wreq_rd_en;

    assign mc_rreq_rdata = rreq_rdata;
    assign mc_rreq_empty = rreq_empty;
    assign rreq_rd_en    = mc_rreq_rd_en;

    assign s_axi_bid   = bresp_err_valid ? bresp_err_id : bresp_rdata;
    assign s_axi_bresp = bresp_err_valid ? 2'b10 : 2'b00;
    assign s_axi_buser = {C_AXI_BUSER_WIDTH{1'b0}};
    assign s_axi_bvalid = bresp_err_valid || !bresp_empty;
    assign bresp_rd_en = !bresp_err_valid && s_axi_bvalid && s_axi_bready;

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
