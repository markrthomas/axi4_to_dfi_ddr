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

    axi4_to_dfi_bridge dut (
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

    // Tie unused DFI handshakes (no update traffic)
    initial begin
        dfi_ctrlupd_ack = 1'b0;
        dfi_phyupd_ack  = 1'b0;
        dfi_lp_ctrl_ack = 1'b0;
    end

    //-------------------------------------------------------------------------
    // Last AR address seen on AXI (scoreboard; avoids sampling DFI addr races).
    //-------------------------------------------------------------------------
    reg [C_AXI_ADDR_WIDTH-1:0] tb_last_read_addr;

    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn)
            tb_last_read_addr <= {C_AXI_ADDR_WIDTH{1'b0}};
        else if (s_axi_arvalid && s_axi_arready)
            tb_last_read_addr <= s_axi_araddr;
    end

    //-------------------------------------------------------------------------
    // Minimal PHY read-return model (dfi_clk domain)
    //-------------------------------------------------------------------------
    reg [2:0] phy_rd_pipe;

    always @(posedge dfi_clk or negedge dfi_rst_n) begin
        if (!dfi_rst_n) begin
            phy_rd_pipe      <= 3'b0;
            dfi_rddata_valid <= 1'b0;
            dfi_rddata       <= {DFI_DATA_WIDTH{1'b0}};
        end else begin
            dfi_rddata_valid <= 1'b0;
            phy_rd_pipe <= {phy_rd_pipe[1:0], dfi_rddata_en};
            if (phy_rd_pipe[2]) begin
                dfi_rddata_valid <= 1'b1;
                dfi_rddata <= {32'hA5A5A5A5, 14'h0, tb_last_read_addr[DFI_ADDR_WIDTH-1:0]};
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
    // Single-beat write (AW+W same cycle as DUT allows)
    //-------------------------------------------------------------------------
    task axi_write_single;
        input [C_AXI_ADDR_WIDTH-1:0] addr;
        input [C_AXI_ID_WIDTH-1:0]     id;
        input [C_AXI_DATA_WIDTH-1:0]   data;
        input [STROBE_W-1:0]           strb;
        begin
            // DUT gates AW/W on BREADY; B is not valid during address/data phase.
            s_axi_bready  = 1'b1;
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
            s_axi_bready  = 1'b0;
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

    initial begin
        errors = 0;
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
        repeat (3) @(posedge dfi_clk);
        dfi_init_complete = 1'b1;
        repeat (3) @(posedge axi_aclk);
        axi_aresetn = 1'b1;

        repeat (10) @(posedge axi_aclk);

        // --- Test 1: write then read same line ---
        axi_write_single(32'h0000_1000, 4'h3, 64'hDEADBEEF_00000001, 8'hFF);
        axi_wait_b(4'h3);
        axi_read_single(32'h0000_1000, 4'h4);
        axi_wait_r(4'h4, expected_rdata(32'h0000_1000));

        // --- Test 2: another address ---
        axi_write_single(32'h0000_2008, 4'h1, 64'hCAFEBABE_12345678, 8'hFF);
        axi_wait_b(4'h1);
        axi_read_single(32'h0000_2008, 4'h2);
        axi_wait_r(4'h2, expected_rdata(32'h0000_2008));

        repeat (20) @(posedge axi_aclk);

        if (errors == 0)
            $display("PASS: tb_axi4_to_dfi_bridge (basic write/read checks)");
        else
            $display("FAIL: tb_axi4_to_dfi_bridge errors=%0d", errors);
        $finish;
    end

endmodule
