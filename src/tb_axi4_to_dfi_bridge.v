//=============================================================================
// tb_axi4_to_dfi_bridge.v
//
// Self-contained testbench + basic tests for axi4_to_dfi_bridge.
// Run (from repo root):  make -C test run
// Or: iverilog -g2001 -Wall -o sim.vvp ... && vvp sim.vvp [+vcd]
//=============================================================================

`timescale 1ns / 1ps

module tb;

    // VCD for gtkwave: vvp ... +vcd  (see test/Makefile target `vcd`)
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/sim.vcd");
            $dumpvars(0, tb);
        end
    end

    // Match DUT defaults
    localparam integer C_AXI_ADDR_WIDTH = 32;
    localparam integer C_AXI_DATA_WIDTH = 64;
    localparam integer C_AXI_ID_WIDTH   = 4;
    localparam integer USER_W           = 1;
    localparam integer DFI_ADDR_WIDTH   = 18;
    localparam integer DFI_BANK_WIDTH   = 3;
    localparam integer DFI_DATA_WIDTH   = 64;
    localparam integer DFI_MASK_WIDTH   = DFI_DATA_WIDTH / 8;
    localparam integer STROBE_W         = C_AXI_DATA_WIDTH / 8;

    localparam [2:0] AXI_SIZE_FULL = 3'd3; // 2**3 = 8 bytes for 64-bit bus

    integer errors;
    integer tb_qi;
    integer tb_init_start_hi;

    // Asynchronous clocks (CDC path in DUT)
    reg axi_aclk;
    reg dfi_clk;
    reg axi_aresetn;
    reg dfi_rst_n;

    initial axi_aclk = 1'b0;
    always #10 axi_aclk = ~axi_aclk; // 50 MHz

    initial dfi_clk = 1'b0;
    always #7  dfi_clk = ~dfi_clk;   // ~71 MHz

    // AXI master drive
    reg [C_AXI_ID_WIDTH-1:0]     s_axi_awid;
    reg [C_AXI_ADDR_WIDTH-1:0]   s_axi_awaddr;
    reg [7:0]                    s_axi_awlen;
    reg [2:0]                    s_axi_awsize;
    reg [1:0]                    s_axi_awburst;
    reg                          s_axi_awlock;
    reg [3:0]                    s_axi_awcache;
    reg [2:0]                    s_axi_awprot;
    reg [3:0]                    s_axi_awqos;
    reg [3:0]                    s_axi_awregion;
    reg [USER_W-1:0]             s_axi_awuser;
    reg                          s_axi_awvalid;

    reg [C_AXI_DATA_WIDTH-1:0]   s_axi_wdata;
    reg [STROBE_W-1:0]           s_axi_wstrb;
    reg                          s_axi_wlast;
    reg [USER_W-1:0]             s_axi_wuser;
    reg                          s_axi_wvalid;

    wire                         s_axi_awready;
    wire                         s_axi_wready;

    reg                          s_axi_bready;
    wire [C_AXI_ID_WIDTH-1:0]    s_axi_bid;
    wire [1:0]                   s_axi_bresp;
    wire [USER_W-1:0]            s_axi_buser;
    wire                         s_axi_bvalid;

    reg [C_AXI_ID_WIDTH-1:0]     s_axi_arid;
    reg [C_AXI_ADDR_WIDTH-1:0]   s_axi_araddr;
    reg [7:0]                    s_axi_arlen;
    reg [2:0]                    s_axi_arsize;
    reg [1:0]                    s_axi_arburst;
    reg                          s_axi_arlock;
    reg [3:0]                    s_axi_arcache;
    reg [2:0]                    s_axi_arprot;
    reg [3:0]                    s_axi_arqos;
    reg [3:0]                    s_axi_arregion;
    reg [USER_W-1:0]             s_axi_aruser;
    reg                          s_axi_arvalid;
    wire                         s_axi_arready;

    reg                          s_axi_rready;
    wire [C_AXI_ID_WIDTH-1:0]    s_axi_rid;
    wire [C_AXI_DATA_WIDTH-1:0]  s_axi_rdata;
    wire [1:0]                   s_axi_rresp;
    wire                         s_axi_rlast;
    wire [USER_W-1:0]            s_axi_ruser;
    wire                         s_axi_rvalid;

    // DFI PHY side
    wire                         dfi_ctrlupd_req;
    reg                          dfi_ctrlupd_ack;
    wire                         dfi_phyupd_req;
    reg                          dfi_phyupd_ack;
    wire                         dfi_lp_ctrl_req;
    reg                          dfi_lp_ctrl_ack;
    wire                         dfi_init_start;
    reg                          dfi_init_complete;

    wire [DFI_ADDR_WIDTH-1:0]    dfi_address;
    wire [DFI_BANK_WIDTH-1:0]    dfi_bank;
    wire                         dfi_ras_n;
    wire                         dfi_cas_n;
    wire                         dfi_we_n;
    wire [0:0]                   dfi_cs_n;
    wire [0:0]                   dfi_odt;
    wire [0:0]                   dfi_cke;
    wire                         dfi_act_n;
    wire [DFI_DATA_WIDTH-1:0]    dfi_wrdata;
    wire [DFI_MASK_WIDTH-1:0]    dfi_wrdata_mask;
    wire                         dfi_wrdata_en;
    reg [DFI_DATA_WIDTH-1:0]     dfi_rddata;
    reg                          dfi_rddata_valid;
    wire                         dfi_rddata_en;

    axi4_to_dfi_bridge #(
        .DFI_INIT_START_CYCLES(4)
    ) dut (
        .axi_aclk           (axi_aclk),
        .axi_aresetn        (axi_aresetn),
        .s_axi_awid         (s_axi_awid),
        .s_axi_awaddr       (s_axi_awaddr),
        .s_axi_awlen        (s_axi_awlen),
        .s_axi_awsize       (s_axi_awsize),
        .s_axi_awburst      (s_axi_awburst),
        .s_axi_awlock       (s_axi_awlock),
        .s_axi_awcache      (s_axi_awcache),
        .s_axi_awprot       (s_axi_awprot),
        .s_axi_awqos        (s_axi_awqos),
        .s_axi_awregion     (s_axi_awregion),
        .s_axi_awuser       (s_axi_awuser),
        .s_axi_awvalid      (s_axi_awvalid),
        .s_axi_awready      (s_axi_awready),
        .s_axi_wdata        (s_axi_wdata),
        .s_axi_wstrb        (s_axi_wstrb),
        .s_axi_wlast        (s_axi_wlast),
        .s_axi_wuser        (s_axi_wuser),
        .s_axi_wvalid       (s_axi_wvalid),
        .s_axi_wready       (s_axi_wready),
        .s_axi_bid          (s_axi_bid),
        .s_axi_bresp        (s_axi_bresp),
        .s_axi_buser        (s_axi_buser),
        .s_axi_bvalid       (s_axi_bvalid),
        .s_axi_bready       (s_axi_bready),
        .s_axi_arid         (s_axi_arid),
        .s_axi_araddr       (s_axi_araddr),
        .s_axi_arlen        (s_axi_arlen),
        .s_axi_arsize       (s_axi_arsize),
        .s_axi_arburst      (s_axi_arburst),
        .s_axi_arlock       (s_axi_arlock),
        .s_axi_arcache      (s_axi_arcache),
        .s_axi_arprot       (s_axi_arprot),
        .s_axi_arqos        (s_axi_arqos),
        .s_axi_arregion     (s_axi_arregion),
        .s_axi_aruser       (s_axi_aruser),
        .s_axi_arvalid      (s_axi_arvalid),
        .s_axi_arready      (s_axi_arready),
        .s_axi_rid          (s_axi_rid),
        .s_axi_rdata        (s_axi_rdata),
        .s_axi_rresp        (s_axi_rresp),
        .s_axi_rlast        (s_axi_rlast),
        .s_axi_ruser        (s_axi_ruser),
        .s_axi_rvalid       (s_axi_rvalid),
        .s_axi_rready       (s_axi_rready),
        .dfi_clk            (dfi_clk),
        .dfi_rst_n          (dfi_rst_n),
        .dfi_ctrlupd_req    (dfi_ctrlupd_req),
        .dfi_ctrlupd_ack    (dfi_ctrlupd_ack),
        .dfi_phyupd_req     (dfi_phyupd_req),
        .dfi_phyupd_ack     (dfi_phyupd_ack),
        .dfi_lp_ctrl_req    (dfi_lp_ctrl_req),
        .dfi_lp_ctrl_ack    (dfi_lp_ctrl_ack),
        .dfi_init_start     (dfi_init_start),
        .dfi_init_complete  (dfi_init_complete),
        .dfi_address        (dfi_address),
        .dfi_bank           (dfi_bank),
        .dfi_ras_n          (dfi_ras_n),
        .dfi_cas_n          (dfi_cas_n),
        .dfi_we_n           (dfi_we_n),
        .dfi_cs_n           (dfi_cs_n),
        .dfi_odt            (dfi_odt),
        .dfi_cke            (dfi_cke),
        .dfi_act_n          (dfi_act_n),
        .dfi_wrdata         (dfi_wrdata),
        .dfi_wrdata_mask    (dfi_wrdata_mask),
        .dfi_wrdata_en      (dfi_wrdata_en),
        .dfi_rddata         (dfi_rddata),
        .dfi_rddata_valid   (dfi_rddata_valid),
        .dfi_rddata_en      (dfi_rddata_en)
    );

    //-------------------------------------------------------------------------
    // DFI SDRAM-style command counters (dfi_clk): PRE / ACT / READ CAS / WRITE CAS
    //-------------------------------------------------------------------------
    reg                          mon_en;
    reg                          tb_mon_reset;
    reg [15:0]                   mon_pre;
    reg [15:0]                   mon_act;
    reg [15:0]                   mon_rdcas;
    reg [15:0]                   mon_wrcas;

    initial tb_mon_reset = 1'b0;

    always @(posedge dfi_clk or negedge dfi_rst_n) begin
        if (!dfi_rst_n) begin
            mon_pre    <= 16'd0;
            mon_act    <= 16'd0;
            mon_rdcas  <= 16'd0;
            mon_wrcas  <= 16'd0;
        end else if (tb_mon_reset) begin
            mon_pre    <= 16'd0;
            mon_act    <= 16'd0;
            mon_rdcas  <= 16'd0;
            mon_wrcas  <= 16'd0;
        end else if (dfi_init_complete && mon_en && !dfi_cs_n[0]) begin
            if (!dfi_ras_n && dfi_cas_n && !dfi_we_n)
                mon_pre <= mon_pre + 16'd1;
            else if (!dfi_ras_n && dfi_cas_n && dfi_we_n)
                mon_act <= mon_act + 16'd1;
            else if (dfi_ras_n && !dfi_cas_n && dfi_we_n)
                mon_rdcas <= mon_rdcas + 16'd1;
            else if (dfi_ras_n && !dfi_cas_n && !dfi_we_n)
                mon_wrcas <= mon_wrcas + 16'd1;
        end
    end

    // Pack AXI address like DUT MC decode: bank[26:24], row[23:10], col[9:0]
    function [C_AXI_ADDR_WIDTH-1:0] tb_mc_addr;
        input [DFI_BANK_WIDTH-1:0] bank;
        input [13:0]               row; // MC_ROW_BITS=14
        input [9:0]                col; // MC_COL_BITS=10
        begin
            tb_mc_addr = { {5{1'b0}}, bank, row, col };
        end
    endfunction

    task tb_mon_clear;
        begin
            @(posedge dfi_clk);
            tb_mon_reset = 1'b1;
            @(posedge dfi_clk);
            tb_mon_reset = 1'b0;
        end
    endtask

    // Drop any completed AXI R/B beats (e.g. before stressing CDC FIFO depth)
    task tb_flush_axi_rsp;
        begin
            while (s_axi_rvalid) begin
                s_axi_rready = 1'b1;
                @(posedge axi_aclk);
            end
            s_axi_rready = 1'b0;
            while (s_axi_bvalid) begin
                s_axi_bready = 1'b1;
                @(posedge axi_aclk);
            end
            s_axi_bready = 1'b0;
        end
    endtask

    // Allow MC FSM + CDC to finish after last AXI handshake
    task tb_wait_dfi_mc;
        input integer dfi_cycles;
        integer k;
        begin
            for (k = 0; k < dfi_cycles; k = k + 1)
                @(posedge dfi_clk);
        end
    endtask

    task tb_check_mc_counts;
        input integer exp_pre;
        input integer exp_act;
        input integer exp_rdcas;
        input integer exp_wrcas;
        begin
            if (mon_pre != exp_pre) begin
                $display("FAIL: MC PRE count exp %0d got %0d", exp_pre, mon_pre);
                errors = errors + 1;
            end
            if (mon_act != exp_act) begin
                $display("FAIL: MC ACT count exp %0d got %0d", exp_act, mon_act);
                errors = errors + 1;
            end
            if (mon_rdcas != exp_rdcas) begin
                $display("FAIL: MC READ CAS count exp %0d got %0d", exp_rdcas, mon_rdcas);
                errors = errors + 1;
            end
            if (mon_wrcas != exp_wrcas) begin
                $display("FAIL: MC WRITE CAS count exp %0d got %0d", exp_wrcas, mon_wrcas);
                errors = errors + 1;
            end
        end
    endtask

    // Tie unused DFI handshakes (no update traffic)
    initial begin
        dfi_ctrlupd_ack = 1'b0;
        dfi_phyupd_ack  = 1'b0;
        dfi_lp_ctrl_ack = 1'b0;
    end

    //-------------------------------------------------------------------------
    // Queue AR addresses so the PHY model returns data for reads in issue order.
    //-------------------------------------------------------------------------
    reg [C_AXI_ADDR_WIDTH-1:0] tb_read_addr_q [0:15];
    integer tb_read_addr_wr_ptr;
    integer tb_read_addr_rd_ptr;
    // Pulse high (dfi_clk domain) to clear PHY read pipeline and rd_ptr
    reg                          tb_read_model_rst;
    // When high, drop the dfi_rddata_valid pulse (read MC timeout / SLVERR path)
    reg                          tb_phy_suppress_rddv;

    initial tb_read_model_rst = 1'b0;
    initial tb_phy_suppress_rddv = 1'b0;

    // wr_ptr / queue entries updated only from tasks (avoid race with arvalid drop same cycle)
    task tb_push_read_addr;
        input [C_AXI_ADDR_WIDTH-1:0] addr;
        begin
            tb_read_addr_q[tb_read_addr_wr_ptr[3:0]] = addr;
            tb_read_addr_wr_ptr = tb_read_addr_wr_ptr + 1;
        end
    endtask

    task tb_clear_read_addr_q;
        begin
            tb_read_addr_wr_ptr = 0;
            for (tb_qi = 0; tb_qi < 16; tb_qi = tb_qi + 1)
                tb_read_addr_q[tb_qi] = {C_AXI_ADDR_WIDTH{1'b0}};
        end
    endtask

    //-------------------------------------------------------------------------
    // PHY read-return model (dfi_clk domain): align with DUT MC_CL after READ CAS
    //-------------------------------------------------------------------------
    localparam integer TB_PHY_MC_CL = 6;

    reg [7:0] phy_rd_lat;

    always @(posedge dfi_clk or negedge dfi_rst_n) begin
        if (!dfi_rst_n) begin
            phy_rd_lat            <= 8'd0;
            dfi_rddata_valid      <= 1'b0;
            dfi_rddata            <= {DFI_DATA_WIDTH{1'b0}};
            tb_read_addr_rd_ptr   <= 0;
        end else if (tb_read_model_rst) begin
            phy_rd_lat            <= 8'd0;
            dfi_rddata_valid      <= 1'b0;
            dfi_rddata            <= {DFI_DATA_WIDTH{1'b0}};
            tb_read_addr_rd_ptr   <= 0;
        end else begin
            dfi_rddata_valid <= 1'b0;
            if (dfi_rddata_en)
                phy_rd_lat <= TB_PHY_MC_CL[7:0];
            else if (phy_rd_lat != 8'd0) begin
                if (phy_rd_lat == 8'd1) begin
                    if (!tb_phy_suppress_rddv) begin
                        dfi_rddata_valid <= 1'b1;
                        dfi_rddata <= {32'hA5A5A5A5, 14'h0,
                                       tb_read_addr_q[tb_read_addr_rd_ptr[3:0]][DFI_ADDR_WIDTH-1:0]};
                    end
                    // Advance queue whenever the MC read window ends (valid or suppressed timeout)
                    tb_read_addr_rd_ptr <= tb_read_addr_rd_ptr + 1;
                    phy_rd_lat <= 8'd0;
                end else
                    phy_rd_lat <= phy_rd_lat - 8'd1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Expected read data (must match PHY model)
    //-------------------------------------------------------------------------
    function [C_AXI_DATA_WIDTH-1:0] expected_rdata;
        input [C_AXI_ADDR_WIDTH-1:0] addr;
        begin
            expected_rdata = {32'hA5A5A5A5, 14'h0, addr[DFI_ADDR_WIDTH-1:0]};
        end
    endfunction

    //-------------------------------------------------------------------------
    // AXI idle defaults
    //-------------------------------------------------------------------------
    task axi_idle;
        begin
            s_axi_awvalid  = 1'b0;
            s_axi_wvalid   = 1'b0;
            s_axi_arvalid  = 1'b0;
            // Hold low until a response is visible (avoid 1-cycle B/R with bready=1).
            s_axi_bready   = 1'b0;
            s_axi_rready   = 1'b0;
            s_axi_awlen    = 8'd0;
            s_axi_arlen    = 8'd0;
            s_axi_awsize   = AXI_SIZE_FULL;
            s_axi_arsize   = AXI_SIZE_FULL;
            s_axi_awburst  = 2'b01;
            s_axi_arburst  = 2'b01;
            s_axi_awlock   = 1'b0;
            s_axi_arlock   = 1'b0;
            s_axi_awcache  = 4'b0;
            s_axi_arcache  = 4'b0;
            s_axi_awprot   = 3'b0;
            s_axi_arprot   = 3'b0;
            s_axi_awqos    = 4'b0;
            s_axi_arqos    = 4'b0;
            s_axi_awregion = 4'b0;
            s_axi_arregion = 4'b0;
            s_axi_awuser   = {USER_W{1'b0}};
            s_axi_wuser    = {USER_W{1'b0}};
            s_axi_aruser   = {USER_W{1'b0}};
        end
    endtask

    //-------------------------------------------------------------------------
    // Single-beat write helpers
    //-------------------------------------------------------------------------
    task axi_write_single;
        input [C_AXI_ADDR_WIDTH-1:0] addr;
        input [C_AXI_ID_WIDTH-1:0]     id;
        input [C_AXI_DATA_WIDTH-1:0]   data;
        input [STROBE_W-1:0]           strb;
        begin
            s_axi_awid    = id;
            s_axi_awaddr  = addr;
            s_axi_wdata   = data;
            s_axi_wstrb   = strb;
            s_axi_wlast   = 1'b1;
            s_axi_awvalid = 1'b1;
            s_axi_wvalid  = 1'b1;
            @(posedge axi_aclk);
            while (!(s_axi_awready && s_axi_wready))
                @(posedge axi_aclk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
        end
    endtask

    // INCR write burst: awlen = beats-1 (max 3 for default DUT), full-width, one B after all beats
    task axi_write_incr_burst;
        input [C_AXI_ADDR_WIDTH-1:0] base_addr;
        input [C_AXI_ID_WIDTH-1:0]     id;
        input [7:0]                    awlen;
        input [C_AXI_DATA_WIDTH-1:0]   first_data;
        integer k;
        begin
            s_axi_awid    = id;
            s_axi_awaddr  = base_addr;
            s_axi_awlen   = awlen;
            s_axi_awburst = 2'b01;
            s_axi_awvalid = 1'b1;
            @(posedge axi_aclk);
            while (!s_axi_awready)
                @(posedge axi_aclk);
            s_axi_awvalid = 1'b0;

            for (k = 0; k <= awlen; k = k + 1) begin
                s_axi_wdata   = first_data + (k * 64'h8);
                s_axi_wstrb   = 8'hFF;
                s_axi_wlast   = (k == awlen);
                s_axi_wvalid  = 1'b1;
                @(posedge axi_aclk);
                while (!s_axi_wready)
                    @(posedge axi_aclk);
                s_axi_wvalid  = 1'b0;
            end
            s_axi_awlen = 8'd0;
        end
    endtask

    task axi_write_aw_then_w;
        input [C_AXI_ADDR_WIDTH-1:0] addr;
        input [C_AXI_ID_WIDTH-1:0]     id;
        input [C_AXI_DATA_WIDTH-1:0]   data;
        input [STROBE_W-1:0]           strb;
        begin
            s_axi_awid    = id;
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            @(posedge axi_aclk);
            while (!s_axi_awready)
                @(posedge axi_aclk);
            s_axi_awvalid = 1'b0;

            repeat (2) @(posedge axi_aclk);

            s_axi_wdata   = data;
            s_axi_wstrb   = strb;
            s_axi_wlast   = 1'b1;
            s_axi_wvalid  = 1'b1;
            @(posedge axi_aclk);
            while (!s_axi_wready)
                @(posedge axi_aclk);
            s_axi_wvalid  = 1'b0;
        end
    endtask

    task axi_write_w_then_aw;
        input [C_AXI_ADDR_WIDTH-1:0] addr;
        input [C_AXI_ID_WIDTH-1:0]     id;
        input [C_AXI_DATA_WIDTH-1:0]   data;
        input [STROBE_W-1:0]           strb;
        begin
            s_axi_wdata   = data;
            s_axi_wstrb   = strb;
            s_axi_wlast   = 1'b1;
            s_axi_wvalid  = 1'b1;
            @(posedge axi_aclk);
            while (!s_axi_wready)
                @(posedge axi_aclk);
            s_axi_wvalid  = 1'b0;

            repeat (2) @(posedge axi_aclk);

            s_axi_awid    = id;
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            @(posedge axi_aclk);
            while (!s_axi_awready)
                @(posedge axi_aclk);
            s_axi_awvalid = 1'b0;
        end
    endtask

    task axi_wait_b;
        input [C_AXI_ID_WIDTH-1:0] exp_id;
        begin
            while (!s_axi_bvalid)
                @(posedge axi_aclk);
            if (s_axi_bid !== exp_id) begin
                $display("FAIL: BID mismatch exp %h got %h", exp_id, s_axi_bid);
                errors = errors + 1;
            end
            if (s_axi_bresp !== 2'b00) begin
                $display("FAIL: BRESP not OKAY: %b", s_axi_bresp);
                errors = errors + 1;
            end
            s_axi_bready = 1'b1;
            @(posedge axi_aclk);
            s_axi_bready = 1'b0;
        end
    endtask

    task axi_wait_b_stall;
        input [C_AXI_ID_WIDTH-1:0] exp_id;
        input integer stall_cycles;
        integer i;
        reg [C_AXI_ID_WIDTH-1:0] held_bid;
        begin
            while (!s_axi_bvalid)
                @(posedge axi_aclk);
            held_bid = s_axi_bid;
            for (i = 0; i < stall_cycles; i = i + 1) begin
                if (!s_axi_bvalid) begin
                    $display("FAIL: BVALID dropped during backpressure");
                    errors = errors + 1;
                end
                if (s_axi_bid !== held_bid) begin
                    $display("FAIL: BID changed under backpressure exp %h got %h", held_bid, s_axi_bid);
                    errors = errors + 1;
                end
                @(posedge axi_aclk);
            end
            if (held_bid !== exp_id) begin
                $display("FAIL: BID mismatch exp %h got %h", exp_id, held_bid);
                errors = errors + 1;
            end
            if (s_axi_bresp !== 2'b00) begin
                $display("FAIL: BRESP not OKAY: %b", s_axi_bresp);
                errors = errors + 1;
            end
            s_axi_bready = 1'b1;
            @(posedge axi_aclk);
            s_axi_bready = 1'b0;
            while (s_axi_bvalid && (s_axi_bid === held_bid))
                @(posedge axi_aclk);
        end
    endtask

    //-------------------------------------------------------------------------
    // Single-beat read
    //-------------------------------------------------------------------------
    task axi_read_single;
        input [C_AXI_ADDR_WIDTH-1:0] addr;
        input [C_AXI_ID_WIDTH-1:0]     id;
        begin
            s_axi_arid    = id;
            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b1;
            @(posedge axi_aclk);
            while (!s_axi_arready)
                @(posedge axi_aclk);
            tb_push_read_addr(s_axi_araddr);
            s_axi_arvalid = 1'b0;
        end
    endtask

    task axi_wait_r;
        input [C_AXI_ID_WIDTH-1:0]     exp_id;
        input [C_AXI_DATA_WIDTH-1:0]   exp_data;
        begin
            while (!s_axi_rvalid)
                @(posedge axi_aclk);
            if (s_axi_rid !== exp_id) begin
                $display("FAIL: RID mismatch exp %h got %h", exp_id, s_axi_rid);
                errors = errors + 1;
            end
            if (s_axi_rdata !== exp_data) begin
                $display("FAIL: RDATA mismatch exp %h got %h", exp_data, s_axi_rdata);
                errors = errors + 1;
            end
            if (s_axi_rresp !== 2'b00) begin
                $display("FAIL: RRESP not OKAY: %b", s_axi_rresp);
                errors = errors + 1;
            end
            if (s_axi_rlast !== 1'b1) begin
                $display("FAIL: RLAST not set");
                errors = errors + 1;
            end
            s_axi_rready = 1'b1;
            @(posedge axi_aclk);
            s_axi_rready = 1'b0;
        end
    endtask

    // SLVERR read (decode error or MC read-data timeout)
    task axi_wait_r_slverr;
        input [C_AXI_ID_WIDTH-1:0] exp_id;
        begin
            while (!s_axi_rvalid)
                @(posedge axi_aclk);
            if (s_axi_rid !== exp_id) begin
                $display("FAIL: SLVERR RID mismatch exp %h got %h", exp_id, s_axi_rid);
                errors = errors + 1;
            end
            if (s_axi_rdata !== {C_AXI_DATA_WIDTH{1'b0}}) begin
                $display("FAIL: SLVERR RDATA exp 0 got %h", s_axi_rdata);
                errors = errors + 1;
            end
            if (s_axi_rresp !== 2'b10) begin
                $display("FAIL: SLVERR RRESP exp 10 got %b", s_axi_rresp);
                errors = errors + 1;
            end
            if (s_axi_rlast !== 1'b1) begin
                $display("FAIL: SLVERR RLAST not set");
                errors = errors + 1;
            end
            s_axi_rready = 1'b1;
            @(posedge axi_aclk);
            s_axi_rready = 1'b0;
        end
    endtask

    task axi_wait_r_stall;
        input [C_AXI_ID_WIDTH-1:0]     exp_id;
        input [C_AXI_DATA_WIDTH-1:0]   exp_data;
        input integer stall_cycles;
        integer i;
        reg [C_AXI_ID_WIDTH-1:0] held_rid;
        reg [C_AXI_DATA_WIDTH-1:0] held_rdata;
        begin
            while (!s_axi_rvalid)
                @(posedge axi_aclk);
            held_rid   = s_axi_rid;
            held_rdata = s_axi_rdata;
            for (i = 0; i < stall_cycles; i = i + 1) begin
                if (!s_axi_rvalid) begin
                    $display("FAIL: RVALID dropped during backpressure");
                    errors = errors + 1;
                end
                if (s_axi_rid !== held_rid) begin
                    $display("FAIL: RID changed under backpressure exp %h got %h", held_rid, s_axi_rid);
                    errors = errors + 1;
                end
                if (s_axi_rdata !== held_rdata) begin
                    $display("FAIL: RDATA changed under backpressure exp %h got %h", held_rdata, s_axi_rdata);
                    errors = errors + 1;
                end
                @(posedge axi_aclk);
            end
            if (held_rid !== exp_id) begin
                $display("FAIL: RID mismatch exp %h got %h", exp_id, held_rid);
                errors = errors + 1;
            end
            if (held_rdata !== exp_data) begin
                $display("FAIL: RDATA mismatch exp %h got %h", exp_data, held_rdata);
                errors = errors + 1;
            end
            if (s_axi_rresp !== 2'b00) begin
                $display("FAIL: RRESP not OKAY: %b", s_axi_rresp);
                errors = errors + 1;
            end
            if (s_axi_rlast !== 1'b1) begin
                $display("FAIL: RLAST not set");
                errors = errors + 1;
            end
            s_axi_rready = 1'b1;
            @(posedge axi_aclk);
            s_axi_rready = 1'b0;
            while (s_axi_rvalid && (s_axi_rid === held_rid) && (s_axi_rdata === held_rdata))
                @(posedge axi_aclk);
        end
    endtask

    initial begin
        errors = 0;
        mon_en = 1'b0;
        tb_read_addr_wr_ptr = 0;
        axi_aresetn = 1'b0;
        dfi_rst_n   = 1'b0;
        dfi_init_complete = 1'b0;
        axi_idle;
        s_axi_awid = 0;
        s_axi_arid = 0;
        s_axi_awaddr = 0;
        s_axi_araddr = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;

        repeat (5) @(posedge axi_aclk);
        @(negedge dfi_clk);
        dfi_rst_n = 1'b1;
        tb_init_start_hi = 0;
        repeat (12) @(posedge dfi_clk) begin
            if (dfi_init_start)
                tb_init_start_hi = tb_init_start_hi + 1;
        end
        if (tb_init_start_hi !== 4) begin
            $display("FAIL: dfi_init_start high cycles exp 4 got %0d", tb_init_start_hi);
            errors = errors + 1;
        end
        repeat (3) @(posedge axi_aclk);
        axi_aresetn = 1'b1;

        repeat (4) @(posedge axi_aclk);

        // --- Test 1: accepted writes must not execute before DFI init completes ---
        axi_write_single(32'h0000_0100, 4'hA, 64'hFACEFACE_00000001, 8'hFF);
        repeat (6) begin
            @(posedge axi_aclk);
            if (s_axi_bvalid) begin
                $display("FAIL: Unexpected BVALID while init is incomplete");
                errors = errors + 1;
            end
        end
        repeat (6) begin
            @(posedge dfi_clk);
            if (dfi_wrdata_en || dfi_rddata_en) begin
                $display("FAIL: DFI command issued before init complete");
                errors = errors + 1;
            end
        end
        dfi_init_complete = 1'b1;
        axi_wait_b(4'hA);

        repeat (6) @(posedge axi_aclk);

        // --- Test 2: unsupported requests must complete with SLVERR ---
        // INCR bursts up to AWLEN=3 are supported; use FIXED burst (illegal shape)
        s_axi_awid     = 4'hC;
        s_axi_awaddr   = 32'h0000_0200;
        s_axi_awlen    = 8'd0;
        s_axi_awburst  = 2'b00;
        s_axi_awvalid  = 1'b1;
        @(posedge axi_aclk);
        while (!s_axi_awready)
            @(posedge axi_aclk);
        s_axi_awvalid  = 1'b0;

        s_axi_wdata   = 64'h11112222_33334444;
        s_axi_wstrb   = 8'hFF;
        s_axi_wlast   = 1'b1;
        s_axi_wvalid  = 1'b1;
        @(posedge axi_aclk);
        while (!s_axi_wready)
            @(posedge axi_aclk);
        s_axi_wvalid  = 1'b0;
        s_axi_awburst = 2'b01;

        while (!s_axi_bvalid)
            @(posedge axi_aclk);
        if (s_axi_bid !== 4'hC) begin
            $display("FAIL: BID mismatch exp %h got %h", 4'hC, s_axi_bid);
            errors = errors + 1;
        end
        if (s_axi_bresp !== 2'b10) begin
            $display("FAIL: BRESP mismatch exp %b got %b", 2'b10, s_axi_bresp);
            errors = errors + 1;
        end
        s_axi_bready = 1'b1;
        @(posedge axi_aclk);
        s_axi_bready = 1'b0;

        s_axi_arid    = 4'hD;
        s_axi_araddr  = 32'h0000_0210;
        s_axi_arsize  = 3'd2;
        s_axi_arvalid = 1'b1;
        @(posedge axi_aclk);
        while (!s_axi_arready)
            @(posedge axi_aclk);
        s_axi_arvalid = 1'b0;
        s_axi_arsize  = AXI_SIZE_FULL;

        axi_wait_r_slverr(4'hD);

        repeat (4) @(posedge axi_aclk);

        // --- Test 2b: read data timeout -> SLVERR (PHY withholds dfi_rddata_valid) ---
        tb_phy_suppress_rddv = 1'b1;
        axi_read_single(32'h0000_0280, 4'hE);
        axi_wait_r_slverr(4'hE);
        tb_phy_suppress_rddv = 1'b0;
        repeat (8) @(posedge axi_aclk);

        // --- Test 3: baseline write/read ---
        axi_write_single(32'h0000_1000, 4'h3, 64'hDEADBEEF_00000001, 8'hFF);
        axi_wait_b(4'h3);
        axi_read_single(32'h0000_1000, 4'h4);
        axi_wait_r(4'h4, expected_rdata(32'h0000_1000));

        // --- Test 3b: INCR write burst (AWLEN=3, four beats), single B response ---
        axi_write_incr_burst(32'h0000_9000, 4'h1, 8'd3, 64'hBEEF9000_00000001);
        axi_wait_b(4'h1);
        axi_read_single(32'h0000_9000, 4'h2);
        axi_wait_r(4'h2, expected_rdata(32'h0000_9000));
        axi_read_single(32'h0000_9008, 4'h3);
        axi_wait_r(4'h3, expected_rdata(32'h0000_9008));
        axi_read_single(32'h0000_9010, 4'h4);
        axi_wait_r(4'h4, expected_rdata(32'h0000_9010));
        axi_read_single(32'h0000_9018, 4'h5);
        axi_wait_r(4'h5, expected_rdata(32'h0000_9018));

        // --- Test 4: AW and W on separate cycles ---
        axi_write_aw_then_w(32'h0000_2008, 4'h1, 64'hCAFEBABE_12345678, 8'hFF);
        axi_wait_b(4'h1);
        axi_read_single(32'h0000_2008, 4'h2);
        axi_wait_r(4'h2, expected_rdata(32'h0000_2008));

        // --- Test 5: W can arrive before AW ---
        axi_write_w_then_aw(32'h0000_3010, 4'h5, 64'h11223344_55667788, 8'hF0);
        axi_wait_b(4'h5);

        // --- Test 6: B channel holds valid/data stable under backpressure ---
        axi_write_single(32'h0000_4000, 4'h6, 64'hABCDEF00_00000001, 8'hFF);
        axi_write_single(32'h0000_4008, 4'h7, 64'hABCDEF00_00000002, 8'hFF);
        axi_wait_b_stall(4'h6, 4);
        axi_wait_b(4'h7);

        // --- Test 7: R channel holds valid/data stable under backpressure ---
        axi_read_single(32'h0000_5000, 4'h8);
        axi_wait_r_stall(4'h8, expected_rdata(32'h0000_5000), 4);

        // --- Test 8: memory-controller open-page / row-miss / cold-bank (DFI command counts) ---
        // Realign PHY read queue (test 2 AR is illegal size; no push from axi_read_single)
        s_axi_arvalid = 1'b0;
        tb_clear_read_addr_q;
        tb_read_model_rst = 1'b1;
        repeat (12) @(posedge dfi_clk);
        tb_read_model_rst = 1'b0;
        repeat (6) @(posedge axi_aclk);

        // 8a: open-page read hit: only READ CAS after row already open (different column).
        // Use bank 5 so earlier tests on bank 0 do not force PRE/ACT.
        mon_en = 1'b0;
        axi_write_single(tb_mc_addr(3'd5, 14'd24, 10'd0), 4'hE, 64'hCAFEBABE_00000001, 8'hFF);
        axi_wait_b(4'hE);
        tb_wait_dfi_mc(64);
        tb_mon_clear;
        mon_en = 1'b1;
        axi_read_single(tb_mc_addr(3'd5, 14'd24, 10'd4), 4'hF);
        axi_wait_r(4'hF, expected_rdata(tb_mc_addr(3'd5, 14'd24, 10'd4)));
        tb_wait_dfi_mc(48);
        mon_en = 1'b0;
        tb_check_mc_counts(0, 0, 1, 0);

        // 8b: row miss on same bank — PRE + ACT + WRITE CAS for second row (bank 4)
        mon_en = 1'b0;
        axi_write_single(tb_mc_addr(3'd4, 14'd5, 10'd0), 4'h9, 64'hDEAD6000_00006000, 8'hFF);
        axi_wait_b(4'h9);
        tb_wait_dfi_mc(64);
        tb_mon_clear;
        mon_en = 1'b1;
        axi_write_single(tb_mc_addr(3'd4, 14'd6, 10'd0), 4'h2, 64'hDEAD6800_00006800, 8'hFF);
        axi_wait_b(4'h2);
        tb_wait_dfi_mc(64);
        mon_en = 1'b0;
        tb_check_mc_counts(1, 1, 0, 1);

        // 8c: cold bank (no prior traffic in bank 7) — ACT + WRITE CAS, no PRE
        tb_mon_clear;
        mon_en = 1'b1;
        axi_write_single(32'h0700_0000, 4'hB, 64'hA5B7C0DE_07000000, 8'hFF);
        axi_wait_b(4'hB);
        tb_wait_dfi_mc(64);
        mon_en = 1'b0;
        tb_check_mc_counts(0, 1, 0, 1);

        // --- Test 9: RRESP async FIFO (depth 8) backs up with RREADY low; drain in issue order ---
        s_axi_arvalid = 1'b0;
        tb_flush_axi_rsp;
        s_axi_rready = 1'b0;
        tb_clear_read_addr_q;
        tb_read_model_rst = 1'b1;
        repeat (12) @(posedge dfi_clk);
        tb_read_model_rst = 1'b0;
        repeat (10) @(posedge axi_aclk);

        // Unrolled. Space AR issues and R/B drains on axi_aclk: back-to-back handshakes
        // plus async_fifo read NBAs vs channel assigns can mis-order beats in iverilog.
        axi_read_single(tb_mc_addr(3'd6, 14'd200, 10'd0), 4'h0);
        repeat (2) @(posedge axi_aclk);
        axi_read_single(tb_mc_addr(3'd6, 14'd200, 10'd8), 4'h1);
        repeat (2) @(posedge axi_aclk);
        axi_read_single(tb_mc_addr(3'd6, 14'd200, 10'd16), 4'h2);
        repeat (2) @(posedge axi_aclk);
        axi_read_single(tb_mc_addr(3'd6, 14'd200, 10'd24), 4'h3);
        repeat (2) @(posedge axi_aclk);
        axi_read_single(tb_mc_addr(3'd6, 14'd200, 10'd32), 4'h4);
        repeat (2) @(posedge axi_aclk);
        axi_read_single(tb_mc_addr(3'd6, 14'd200, 10'd40), 4'h5);
        repeat (2) @(posedge axi_aclk);
        axi_read_single(tb_mc_addr(3'd6, 14'd200, 10'd48), 4'h6);
        repeat (2) @(posedge axi_aclk);
        axi_read_single(tb_mc_addr(3'd6, 14'd200, 10'd56), 4'h7);
        tb_wait_dfi_mc(2500);

        axi_wait_r(4'h0, expected_rdata(tb_mc_addr(3'd6, 14'd200, 10'd0)));
        repeat (6) @(posedge axi_aclk);
        axi_wait_r(4'h1, expected_rdata(tb_mc_addr(3'd6, 14'd200, 10'd8)));
        repeat (6) @(posedge axi_aclk);
        axi_wait_r(4'h2, expected_rdata(tb_mc_addr(3'd6, 14'd200, 10'd16)));
        repeat (6) @(posedge axi_aclk);
        axi_wait_r(4'h3, expected_rdata(tb_mc_addr(3'd6, 14'd200, 10'd24)));
        repeat (6) @(posedge axi_aclk);
        axi_wait_r(4'h4, expected_rdata(tb_mc_addr(3'd6, 14'd200, 10'd32)));
        repeat (6) @(posedge axi_aclk);
        axi_wait_r(4'h5, expected_rdata(tb_mc_addr(3'd6, 14'd200, 10'd40)));
        repeat (6) @(posedge axi_aclk);
        axi_wait_r(4'h6, expected_rdata(tb_mc_addr(3'd6, 14'd200, 10'd48)));
        repeat (6) @(posedge axi_aclk);
        axi_wait_r(4'h7, expected_rdata(tb_mc_addr(3'd6, 14'd200, 10'd56)));

        // --- Test 10: BRESP async FIFO (depth 8) backs up with BREADY low; drain in completion order ---
        tb_flush_axi_rsp;
        s_axi_bready = 1'b0;
        tb_wait_dfi_mc(64);
        axi_write_single(tb_mc_addr(3'd2, 14'd88, 10'd0), 4'h0, 64'hB0DF0000_00000000, 8'hFF);
        repeat (2) @(posedge axi_aclk);
        axi_write_single(tb_mc_addr(3'd2, 14'd88, 10'd8), 4'h1, 64'hB0DF0000_00000001, 8'hFF);
        repeat (2) @(posedge axi_aclk);
        axi_write_single(tb_mc_addr(3'd2, 14'd88, 10'd16), 4'h2, 64'hB0DF0000_00000002, 8'hFF);
        repeat (2) @(posedge axi_aclk);
        axi_write_single(tb_mc_addr(3'd2, 14'd88, 10'd24), 4'h3, 64'hB0DF0000_00000003, 8'hFF);
        repeat (2) @(posedge axi_aclk);
        axi_write_single(tb_mc_addr(3'd2, 14'd88, 10'd32), 4'h4, 64'hB0DF0000_00000004, 8'hFF);
        repeat (2) @(posedge axi_aclk);
        axi_write_single(tb_mc_addr(3'd2, 14'd88, 10'd40), 4'h5, 64'hB0DF0000_00000005, 8'hFF);
        repeat (2) @(posedge axi_aclk);
        axi_write_single(tb_mc_addr(3'd2, 14'd88, 10'd48), 4'h6, 64'hB0DF0000_00000006, 8'hFF);
        repeat (2) @(posedge axi_aclk);
        axi_write_single(tb_mc_addr(3'd2, 14'd88, 10'd56), 4'h7, 64'hB0DF0000_00000007, 8'hFF);
        tb_wait_dfi_mc(2500);

        axi_wait_b(4'h0);
        repeat (6) @(posedge axi_aclk);
        axi_wait_b(4'h1);
        repeat (6) @(posedge axi_aclk);
        axi_wait_b(4'h2);
        repeat (6) @(posedge axi_aclk);
        axi_wait_b(4'h3);
        repeat (6) @(posedge axi_aclk);
        axi_wait_b(4'h4);
        repeat (6) @(posedge axi_aclk);
        axi_wait_b(4'h5);
        repeat (6) @(posedge axi_aclk);
        axi_wait_b(4'h6);
        repeat (6) @(posedge axi_aclk);
        axi_wait_b(4'h7);

        // --- Test 11: illegal INCR read with ARLEN != 0 -> SLVERR (no rreq / PHY queue entry) ---
        s_axi_arid    = 4'h4;
        s_axi_araddr  = tb_mc_addr(3'd3, 14'd50, 10'd0);
        s_axi_arlen   = 8'd1;
        s_axi_arburst = 2'b01;
        s_axi_arsize  = AXI_SIZE_FULL;
        s_axi_arvalid = 1'b1;
        @(posedge axi_aclk);
        while (!s_axi_arready)
            @(posedge axi_aclk);
        s_axi_arvalid = 1'b0;
        s_axi_arlen   = 8'd0;
        axi_wait_r_slverr(4'h4);

        // --- Test 12: two outstanding reads with different ARID complete in MC FIFO order ---
        tb_flush_axi_rsp;
        s_axi_rready = 1'b0;
        tb_clear_read_addr_q;
        tb_read_model_rst = 1'b1;
        repeat (12) @(posedge dfi_clk);
        tb_read_model_rst = 1'b0;
        repeat (10) @(posedge axi_aclk);

        axi_read_single(tb_mc_addr(3'd1, 14'd10, 10'd0), 4'hA);
        repeat (2) @(posedge axi_aclk);
        axi_read_single(tb_mc_addr(3'd1, 14'd10, 10'd8), 4'hC);
        tb_wait_dfi_mc(256);
        axi_wait_r(4'hA, expected_rdata(tb_mc_addr(3'd1, 14'd10, 10'd0)));
        repeat (6) @(posedge axi_aclk);
        axi_wait_r(4'hC, expected_rdata(tb_mc_addr(3'd1, 14'd10, 10'd8)));

        repeat (20) @(posedge axi_aclk);

        if (errors == 0)
            $display("PASS: tb_axi4_to_dfi_bridge (FIFO fill + SLVERR + read timeout + backpressure + MC checks)");
        else
            $display("FAIL: tb_axi4_to_dfi_bridge errors=%0d", errors);
        $finish;
    end

endmodule
