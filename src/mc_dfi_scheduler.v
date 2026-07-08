// mc_dfi_scheduler.v — SDRAM-style open-page MC on dfi_clk (DFI command + R/W data timing)
`timescale 1ns / 1ps
module mc_dfi_scheduler #(
    parameter integer C_AXI_ADDR_WIDTH   = 32,
    parameter integer C_AXI_DATA_WIDTH   = 64,
    parameter integer C_AXI_ID_WIDTH     = 4,
    parameter integer DFI_ADDR_WIDTH     = 18,
    parameter integer DFI_BANK_WIDTH     = 3,
    parameter integer DFI_DATA_WIDTH     = 64,
    parameter integer DFI_MASK_WIDTH     = 8,
    parameter integer DFI_CS_WIDTH       = 1,
    parameter integer DFI_ODT_WIDTH      = 1,
    parameter integer DFI_CKE_WIDTH      = 1,
    parameter integer CDC_FIFO_DEPTH     = 8,
    parameter integer DFI_WRITE_ACK_CYCLES = 4,
    parameter integer MC_COL_BITS        = 10,
    parameter integer MC_ROW_BITS        = 14,
    parameter integer MC_T_RP            = 4,
    parameter integer MC_T_RCD           = 4,
    parameter integer MC_T_RAS           = 0,
    parameter integer MC_T_WR            = 0,
    parameter integer MC_CL              = 6,
    parameter integer MC_RD_DV_MAX       = 16,
    parameter integer MC_REFRESH_INTERVAL = 0,
    parameter integer MC_T_RFC           = 0,
    parameter integer WREQ_W             = 8,
    parameter integer RREQ_W             = 8,
    parameter integer BRESP_FIFO_W       = 4,
    parameter integer RRESP_FIFO_W       = 8
) (
    input  wire                          dfi_clk,
    input  wire                          dfi_rst_n,
    input  wire                          dfi_init_complete,
    input  wire [WREQ_W-1:0]             wreq_rdata,
    input  wire                          wreq_empty,
    output wire                          wreq_rd_en,
    input  wire [RREQ_W-1:0]             rreq_rdata,
    input  wire                          rreq_empty,
    output wire                          rreq_rd_en,
    input  wire [DFI_DATA_WIDTH-1:0]     dfi_rddata,
    input  wire                          dfi_rddata_valid,
    input  wire                          bresp_full,
    input  wire                          rresp_full,
    output reg  [DFI_ADDR_WIDTH-1:0]   dfi_address,
    output reg  [DFI_BANK_WIDTH-1:0]     dfi_bank,
    output reg                           dfi_ras_n,
    output reg                           dfi_cas_n,
    output reg                           dfi_we_n,
    output reg  [DFI_CS_WIDTH-1:0]       dfi_cs_n,
    output reg  [DFI_ODT_WIDTH-1:0]      dfi_odt,
    output reg  [DFI_CKE_WIDTH-1:0]      dfi_cke,
    output reg                           dfi_act_n,
    output reg  [DFI_DATA_WIDTH-1:0]    dfi_wrdata,
    output reg  [DFI_MASK_WIDTH-1:0]   dfi_wrdata_mask,
    output reg                           dfi_wrdata_en,
    output reg                           dfi_rddata_en,
    output wire                          bresp_wr_en,
    output wire [BRESP_FIFO_W-1:0]     bresp_wr_data,
    output wire                          rresp_wr_en,
    output wire [RRESP_FIFO_W-1:0]     rresp_wr_data
);
    localparam integer STROBE_W = C_AXI_DATA_WIDTH / 8;
    localparam [C_AXI_ADDR_WIDTH-1:0] WADDR_INCR = C_AXI_DATA_WIDTH / 8;
    localparam integer NBANKS = (1 << DFI_BANK_WIDTH);
    localparam [4:0] ST_IDLE      = 5'd0;
    localparam [4:0] ST_PRE_CMD  = 5'd1;
    localparam [4:0] ST_WAIT_RP  = 5'd2;
    localparam [4:0] ST_ACT_CMD  = 5'd3;
    localparam [4:0] ST_WAIT_RCD = 5'd4;
    localparam [4:0] ST_WR_CMD   = 5'd5;
    localparam [4:0] ST_WAIT_B   = 5'd6;
    localparam [4:0] ST_RD_CMD   = 5'd7;
    localparam [4:0] ST_WAIT_CL  = 5'd8;
    localparam [4:0] ST_WAIT_DV  = 5'd9;
    localparam [4:0] ST_PULSE_R  = 5'd10;
    localparam [4:0] ST_RF_PRE   = 5'd11;
    localparam [4:0] ST_RF_NEXT   = 5'd12;
    localparam [4:0] ST_WAIT_PRE  = 5'd13;
    localparam [4:0] ST_BURST_SLVERR_LOOP = 5'd14;
    localparam [4:0] ST_R_PUSH          = 5'd15;
    localparam [4:0] ST_RF_CMD          = 5'd16;
    localparam [4:0] ST_WAIT_RFC        = 5'd17;

    reg wreq_rd_en_r;
    reg rreq_rd_en_r;
    reg [WREQ_W-1:0] wreq_snapshot;
    reg [RREQ_W-1:0] rreq_snapshot;

    reg  [4:0]               mc_state;
    reg  [7:0]               mc_ctr;
    reg  [4:0]               mc_after_rp;
    reg  [4:0]               mc_after_rcd;
    reg                      mc_is_wr;
    reg  [C_AXI_ID_WIDTH-1:0] mc_id;
    reg  [C_AXI_ADDR_WIDTH-1:0] mc_addr;
    reg  [C_AXI_DATA_WIDTH-1:0] mc_wdata;
    reg  [STROBE_W-1:0]      mc_wstrb;
    reg  [DFI_BANK_WIDTH-1:0] mc_bank;
    reg  [MC_ROW_BITS-1:0]   mc_row;
    reg  [MC_COL_BITS-1:0]   mc_col;
    reg                      mc_wr_last_beat;
    reg  [7:0]               mc_arlen;
    reg  [7:0]               mc_r_beat;
    reg                      mc_rp_slverr;
    reg                      mc_rp_rlast;
    reg  [C_AXI_ID_WIDTH-1:0] mc_rp_id;
    reg  [C_AXI_DATA_WIDTH-1:0] mc_rp_rdata;
    reg  [NBANKS-1:0]        row_open_mask;
    reg  [MC_ROW_BITS-1:0]   open_row_mem [0:NBANKS-1];
    reg  [C_AXI_DATA_WIDTH-1:0] r_capture;
    reg                      mc_got_rddata;
    integer                  open_row_rst_i;

    reg                      rf_active;
    reg [DFI_BANK_WIDTH-1:0] rf_bank;
    reg [31:0]               refresh_ctr;
    reg [15:0]               rfc_ctr;
    reg                      mc_wait_rf;

    reg [7:0]                bank_ras_cnt [0:NBANKS-1];
    reg [7:0]                bank_wr_cnt [0:NBANKS-1];

    // Next AXI byte address for read burst column decode (mc_addr is a reg; sum is a net).
    wire [C_AXI_ADDR_WIDTH-1:0] mc_nxt_addr = mc_addr + WADDR_INCR;

    wire [C_AXI_ADDR_WIDTH-1:0] wreq_addr =
        wreq_snapshot[STROBE_W+C_AXI_DATA_WIDTH +: C_AXI_ADDR_WIDTH];
    wire [C_AXI_ID_WIDTH-1:0] wreq_id =
        wreq_snapshot[STROBE_W+C_AXI_DATA_WIDTH+C_AXI_ADDR_WIDTH +: C_AXI_ID_WIDTH];
    wire [C_AXI_ID_WIDTH-1:0] rreq_id = rreq_snapshot[C_AXI_ADDR_WIDTH +: C_AXI_ID_WIDTH];
    wire [7:0]                  r_snap_arlen = rreq_snapshot[C_AXI_ADDR_WIDTH + C_AXI_ID_WIDTH +: 8];

    wire [0:0] dfi_init_complete_sync;
    wire dfi_mc_ready = dfi_init_complete_sync[0];

    cdc_sync #(.WIDTH(1)) u_sync_dfi_init_complete (
        .dst_clk  (dfi_clk),
        .dst_rst_n(dfi_rst_n),
        .d        ({dfi_init_complete}),
        .q        (dfi_init_complete_sync)
    );

    wire mc_idle = (mc_state == ST_IDLE);

    function bank_pre_ready;
        input [DFI_BANK_WIDTH-1:0] b;
        begin
            bank_pre_ready = (MC_T_RAS == 0 || bank_ras_cnt[b] == 8'd0) &&
                             (MC_T_WR == 0 || bank_wr_cnt[b] == 8'd0);
        end
    endfunction

    wire [DFI_BANK_WIDTH-1:0] wreq_bank = wreq_addr[MC_COL_BITS+MC_ROW_BITS +: DFI_BANK_WIDTH];
    wire [DFI_BANK_WIDTH-1:0] rreq_bank = rreq_snapshot[MC_COL_BITS+MC_ROW_BITS +: DFI_BANK_WIDTH];

    // Per-bank ACT->PRE (tRAS) and WRITE CAS->PRE (tWR) on dfi_clk; see ST_WAIT_PRE.
    genvar gi;
    generate
        for (gi = 0; gi < NBANKS; gi = gi + 1) begin : gen_bank_tim
            always @(posedge dfi_clk or negedge dfi_rst_n) begin
                if (!dfi_rst_n) begin
                    bank_ras_cnt[gi] <= 8'd0;
                    bank_wr_cnt[gi] <= 8'd0;
                end else begin
                    if ((mc_state == ST_ACT_CMD) && (mc_bank == gi)) begin
                        bank_ras_cnt[gi] <= (MC_T_RAS == 0) ? 8'd0 : MC_T_RAS[7:0];
                    end else if ((mc_state == ST_WR_CMD) && (mc_bank == gi)) begin
                        bank_wr_cnt[gi] <= (MC_T_WR == 0) ? 8'd0 : MC_T_WR[7:0];
                    end else if ((mc_state == ST_PRE_CMD) && (mc_bank == gi)) begin
                        bank_ras_cnt[gi] <= 8'd0;
                        bank_wr_cnt[gi] <= 8'd0;
                    end else if ((mc_state == ST_RF_PRE) && (rf_bank == gi)) begin
                        bank_ras_cnt[gi] <= 8'd0;
                        bank_wr_cnt[gi] <= 8'd0;
                    end else if (row_open_mask[gi] ||
                                  ((mc_state == ST_WAIT_RCD) && (mc_bank == gi))) begin
                        if (bank_ras_cnt[gi] != 8'd0)
                            bank_ras_cnt[gi] <= bank_ras_cnt[gi] - 8'd1;
                        if (bank_wr_cnt[gi] != 8'd0)
                            bank_wr_cnt[gi] <= bank_wr_cnt[gi] - 8'd1;
                    end
                end
            end
        end
    endgenerate

    // Block new FIFO pops while a refresh interval has expired (until walk completes).
    wire rf_block_fifo = (MC_REFRESH_INTERVAL > 0) && (refresh_ctr == 32'd0) && !rf_active;
    assign wreq_rd_en = dfi_mc_ready && mc_idle && !rf_block_fifo && !rf_active &&
                        !wreq_rd_en_r && !rreq_rd_en_r && !wreq_empty && !bresp_full;
    assign rreq_rd_en = dfi_mc_ready && mc_idle && !rf_block_fifo && !rf_active &&
                        !wreq_rd_en_r && !rreq_rd_en_r && wreq_empty && !rreq_empty && !rresp_full;

    assign bresp_wr_en = (mc_state == ST_WAIT_B) && (mc_ctr == 8'd1) && !bresp_full &&
                         mc_wr_last_beat;
    assign bresp_wr_data = mc_id;

    wire mc_wait_dv_done = dfi_rddata_valid || (mc_ctr == 8'd0);
    wire rresp_wr_en_rpush = (mc_state == ST_R_PUSH) && !rresp_full;
    wire [RRESP_FIFO_W-1:0] rresp_wr_data_rpush = {
        mc_rp_slverr, mc_rp_rlast, mc_rp_id, mc_rp_rdata
    };
    wire rresp_wr_en_slverr = (mc_state == ST_BURST_SLVERR_LOOP) && !rresp_full;
    wire [RRESP_FIFO_W-1:0] rresp_wr_data_slverr = {
        1'b1,
        (mc_r_beat == mc_arlen),
        mc_id,
        r_capture
    };
    assign rresp_wr_en = rresp_wr_en_rpush || rresp_wr_en_slverr;
    assign rresp_wr_data = rresp_wr_en_slverr ? rresp_wr_data_slverr : rresp_wr_data_rpush;
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
            mc_arlen         <= 8'd0;
            mc_r_beat        <= 8'd0;
            mc_rp_slverr     <= 1'b0;
            mc_rp_rlast      <= 1'b0;
            mc_rp_id         <= {C_AXI_ID_WIDTH{1'b0}};
            mc_rp_rdata      <= {C_AXI_DATA_WIDTH{1'b0}};
            row_open_mask    <= {NBANKS{1'b0}};
            r_capture        <= {C_AXI_DATA_WIDTH{1'b0}};
            mc_got_rddata    <= 1'b0;
            rf_active        <= 1'b0;
            rf_bank          <= {DFI_BANK_WIDTH{1'b0}};
            refresh_ctr      <= (MC_REFRESH_INTERVAL > 0) ? MC_REFRESH_INTERVAL[31:0] : 32'd0;
            rfc_ctr          <= 16'd0;
            mc_wait_rf       <= 1'b0;
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
                    if ((MC_REFRESH_INTERVAL > 0) && (refresh_ctr == 32'd0) && !rf_active &&
                        dfi_mc_ready && !wreq_rd_en_r && !rreq_rd_en_r) begin
                        rf_active <= 1'b1;
                        rf_bank   <= {DFI_BANK_WIDTH{1'b0}};
                        mc_state  <= ST_RF_NEXT;
                    end else if (wreq_rd_en_r) begin
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
                            if (bank_pre_ready(wreq_bank)) begin
                                mc_state   <= ST_PRE_CMD;
                                mc_wait_rf <= 1'b0;
                            end else begin
                                mc_state   <= ST_WAIT_PRE;
                                mc_wait_rf <= 1'b0;
                            end
                        end else
                            mc_state <= ST_WR_CMD;
                    end else if (rreq_rd_en_r) begin
                        mc_is_wr <= 1'b0;
                        mc_arlen <= r_snap_arlen;
                        mc_r_beat <= 8'd0;
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
                            if (bank_pre_ready(rreq_bank)) begin
                                mc_state   <= ST_PRE_CMD;
                                mc_wait_rf <= 1'b0;
                            end else begin
                                mc_state   <= ST_WAIT_PRE;
                                mc_wait_rf <= 1'b0;
                            end
                        end else
                            mc_state <= ST_RD_CMD;
                    end else if ((MC_REFRESH_INTERVAL > 0) && !rf_active && dfi_mc_ready &&
                                 !wreq_rd_en_r && !rreq_rd_en_r && (refresh_ctr != 32'd0))
                        refresh_ctr <= refresh_ctr - 32'd1;
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
                    // bresp_wr_en is (ST_WAIT_B && mc_ctr==1); always enter WAIT_B, ctr=1 when no ack delay
                    mc_ctr   <= (DFI_WRITE_ACK_CYCLES == 0) ? 8'd1 : DFI_WRITE_ACK_CYCLES[7:0];
                    mc_state <= ST_WAIT_B;
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
                    if (mc_wait_dv_done) begin
                        mc_rp_slverr <= (mc_ctr == 8'd0) && !dfi_rddata_valid;
                        mc_rp_rlast  <= (mc_r_beat == mc_arlen);
                        mc_rp_id     <= mc_id;
                        mc_rp_rdata  <= dfi_rddata_valid ? dfi_rddata[C_AXI_DATA_WIDTH-1:0] :
                            r_capture[C_AXI_DATA_WIDTH-1:0];
                        mc_state <= ST_R_PUSH;
                    end else
                        mc_ctr <= mc_ctr - 8'd1;
                end
                ST_R_PUSH: begin
                    if (!rresp_full)
                        mc_state <= ST_PULSE_R;
                end
                ST_PULSE_R: begin
                    if (!mc_is_wr) begin
                        if (mc_r_beat < mc_arlen) begin
                            mc_r_beat <= mc_r_beat + 1'b1;
                            mc_addr     <= mc_addr + WADDR_INCR;
                            mc_col      <= mc_nxt_addr[MC_COL_BITS-1:0];
                            mc_row      <= mc_nxt_addr[MC_COL_BITS +: MC_ROW_BITS];
                            mc_bank     <= mc_nxt_addr[MC_COL_BITS+MC_ROW_BITS +: DFI_BANK_WIDTH];
                            if (mc_got_rddata)
                                mc_state <= ST_RD_CMD;
                            else begin
                                r_capture <= {C_AXI_DATA_WIDTH{1'b0}};
                                mc_state  <= ST_BURST_SLVERR_LOOP;
                            end
                        end else
                            mc_state <= ST_IDLE;
                    end else
                        mc_state <= ST_IDLE;
                end
                ST_BURST_SLVERR_LOOP: begin
                    if (!rresp_full) begin
                        if (mc_r_beat < mc_arlen) begin
                            mc_r_beat <= mc_r_beat + 1'b1;
                            mc_addr     <= mc_addr + WADDR_INCR;
                            mc_col      <= mc_nxt_addr[MC_COL_BITS-1:0];
                            mc_row      <= mc_nxt_addr[MC_COL_BITS +: MC_ROW_BITS];
                            mc_bank     <= mc_nxt_addr[MC_COL_BITS+MC_ROW_BITS +: DFI_BANK_WIDTH];
                            r_capture   <= {C_AXI_DATA_WIDTH{1'b0}};
                        end else
                            mc_state <= ST_IDLE;
                    end
                end
                ST_RF_PRE: begin
                    dfi_bank    <= rf_bank;
                    dfi_address <= open_row_mem[rf_bank];
                    dfi_ras_n   <= 1'b0;
                    dfi_cas_n   <= 1'b1;
                    dfi_we_n    <= 1'b0;
                    dfi_cs_n    <= {DFI_CS_WIDTH{1'b0}};
                    row_open_mask[rf_bank] <= 1'b0;
                    mc_after_rp <= ST_RF_NEXT;
                    if (MC_T_RP == 0)
                        mc_state <= ST_RF_NEXT;
                    else begin
                        mc_ctr   <= MC_T_RP[7:0];
                        mc_state <= ST_WAIT_RP;
                    end
                end
                ST_WAIT_PRE: begin
                    if (mc_wait_rf) begin
                        if (bank_pre_ready(rf_bank))
                            mc_state <= ST_RF_PRE;
                    end else begin
                        if (bank_pre_ready(mc_bank))
                            mc_state <= ST_PRE_CMD;
                    end
                end
                ST_RF_NEXT: begin
                    if (row_open_mask[rf_bank]) begin
                        if (bank_pre_ready(rf_bank))
                            mc_state <= ST_RF_PRE;
                        else begin
                            mc_state   <= ST_WAIT_PRE;
                            mc_wait_rf <= 1'b1;
                        end
                    end else if (rf_bank == {DFI_BANK_WIDTH{1'b1}}) begin
                        // All banks precharged: issue the JEDEC auto-refresh (REF) command.
                        mc_wait_rf <= 1'b0;
                        mc_state   <= ST_RF_CMD;
                    end else begin
                        rf_bank    <= rf_bank + 1'b1;
                        mc_wait_rf <= 1'b0;
                        mc_state   <= ST_RF_NEXT;
                    end
                end
                ST_RF_CMD: begin
                    // Auto-refresh (CBR): CS=0, RAS=0, CAS=0, WE=1, ACT=1; no bank select.
                    dfi_ras_n <= 1'b0;
                    dfi_cas_n <= 1'b0;
                    dfi_we_n  <= 1'b1;
                    dfi_act_n <= 1'b1;
                    dfi_cs_n  <= {DFI_CS_WIDTH{1'b0}};
                    if (MC_T_RFC == 0) begin
                        rf_active   <= 1'b0;
                        refresh_ctr <= MC_REFRESH_INTERVAL[31:0];
                        mc_state    <= ST_IDLE;
                    end else begin
                        rfc_ctr  <= MC_T_RFC[15:0];
                        mc_state <= ST_WAIT_RFC;
                    end
                end
                ST_WAIT_RFC: begin
                    // Hold refresh active (blocks FIFO pops) until tRFC elapses.
                    if (rfc_ctr == 16'd1) begin
                        rf_active   <= 1'b0;
                        refresh_ctr <= MC_REFRESH_INTERVAL[31:0];
                        mc_state    <= ST_IDLE;
                    end else
                        rfc_ctr <= rfc_ctr - 16'd1;
                end
                default: mc_state <= ST_IDLE;
            endcase
        end
    end
endmodule
