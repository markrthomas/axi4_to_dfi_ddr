//=============================================================================
// tb_param_smoke.v — minimal sim for non-default parameters (CI / quick check)
//
// Instantiates axi4_to_dfi_bridge with CDC_FIFO_DEPTH=16 and DFI_INIT_START_CYCLES=0.
// One aligned write + B, one read + R (PHY model matches default MC_CL=6).
//=============================================================================

`timescale 1ns / 1ps

module tb_param_smoke;

    localparam integer C_AXI_ADDR_WIDTH = 32;
    localparam integer C_AXI_DATA_WIDTH = 64;
    localparam integer C_AXI_ID_WIDTH   = 4;
    localparam integer USER_W           = 1;
    localparam integer DFI_ADDR_WIDTH   = 18;
    localparam integer DFI_BANK_WIDTH   = 3;
    localparam integer DFI_DATA_WIDTH   = 64;
    localparam integer DFI_MASK_WIDTH   = DFI_DATA_WIDTH / 8;
    localparam integer STROBE_W         = C_AXI_DATA_WIDTH / 8;
    localparam integer TB_PHY_MC_CL     = 6;

    reg axi_aclk;
    reg dfi_clk;
    reg axi_aresetn;
    reg dfi_rst_n;

    initial axi_aclk = 1'b0;
    always #10 axi_aclk = ~axi_aclk;
    initial dfi_clk = 1'b0;
    always #7  dfi_clk = ~dfi_clk;

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
    reg                          s_axi_bready;
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
    reg                          s_axi_rready;

    wire                         s_axi_awready, s_axi_wready, s_axi_arready;
    wire [C_AXI_ID_WIDTH-1:0]    s_axi_bid;
    wire [1:0]                   s_axi_bresp;
    wire [USER_W-1:0]            s_axi_buser;
    wire                         s_axi_bvalid;
    wire [C_AXI_ID_WIDTH-1:0]    s_axi_rid;
    wire [C_AXI_DATA_WIDTH-1:0]  s_axi_rdata;
    wire [1:0]                   s_axi_rresp;
    wire                         s_axi_rlast;
    wire [USER_W-1:0]            s_axi_ruser;
    wire                         s_axi_rvalid;

    wire                         dfi_ctrlupd_req, dfi_phyupd_req, dfi_lp_ctrl_req, dfi_init_start;
    reg                          dfi_ctrlupd_ack, dfi_phyupd_ack, dfi_lp_ctrl_ack, dfi_init_complete;
    wire [DFI_ADDR_WIDTH-1:0]    dfi_address;
    wire [DFI_BANK_WIDTH-1:0]    dfi_bank;
    wire                         dfi_ras_n, dfi_cas_n, dfi_we_n, dfi_act_n;
    wire [0:0]                   dfi_cs_n, dfi_odt, dfi_cke;
    wire [DFI_DATA_WIDTH-1:0]    dfi_wrdata;
    wire [DFI_MASK_WIDTH-1:0]    dfi_wrdata_mask;
    wire                         dfi_wrdata_en;
    reg [DFI_DATA_WIDTH-1:0]     dfi_rddata;
    reg                          dfi_rddata_valid;
    wire                         dfi_rddata_en;

    function [C_AXI_ADDR_WIDTH-1:0] mc_addr;
        input [DFI_BANK_WIDTH-1:0] bank;
        input [13:0]               row;
        input [9:0]                col;
        begin
            mc_addr = { {5{1'b0}}, bank, row, col };
        end
    endfunction

    axi4_to_dfi_bridge #(
        .CDC_FIFO_DEPTH         (16),
        .DFI_INIT_START_CYCLES  (0)
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

    initial begin
        dfi_ctrlupd_ack = 1'b0;
        dfi_phyupd_ack  = 1'b0;
        dfi_lp_ctrl_ack = 1'b0;
    end

    reg [C_AXI_ADDR_WIDTH-1:0] rd_q [0:3];
    reg [C_AXI_ADDR_WIDTH-1:0] smoke_ra;
    integer rd_wr, rd_rd;
    reg [7:0] phy_rd_lat;

    always @(posedge dfi_clk or negedge dfi_rst_n) begin
        if (!dfi_rst_n) begin
            phy_rd_lat       <= 8'd0;
            dfi_rddata_valid <= 1'b0;
            dfi_rddata       <= {DFI_DATA_WIDTH{1'b0}};
            rd_rd            <= 0;
        end else begin
            dfi_rddata_valid <= 1'b0;
            if (dfi_rddata_en)
                phy_rd_lat <= TB_PHY_MC_CL[7:0];
            else if (phy_rd_lat != 8'd0) begin
                if (phy_rd_lat == 8'd1) begin
                    dfi_rddata_valid <= 1'b1;
                    dfi_rddata <= {32'hA5A5A5A5, 14'h0, rd_q[rd_rd[1:0]][DFI_ADDR_WIDTH-1:0]};
                    rd_rd <= rd_rd + 1;
                    phy_rd_lat <= 8'd0;
                end else
                    phy_rd_lat <= phy_rd_lat - 8'd1;
            end
        end
    end

    integer err;
    initial begin
        err = 0;
        rd_wr = 0;
        rd_rd = 0;
        axi_aresetn = 1'b0;
        dfi_rst_n   = 1'b0;
        dfi_init_complete = 1'b0;
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_arvalid = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_rready  = 1'b0;
        s_axi_awlen   = 8'd0;
        s_axi_arlen   = 8'd0;
        s_axi_awsize  = 3'd3;
        s_axi_arsize  = 3'd3;
        s_axi_awburst = 2'b01;
        s_axi_arburst = 2'b01;

        repeat (5) @(posedge axi_aclk);
        @(negedge dfi_clk);
        dfi_rst_n = 1'b1;
        repeat (8) @(posedge dfi_clk);
        dfi_init_complete = 1'b1;
        repeat (4) @(posedge axi_aclk);
        axi_aresetn = 1'b1;
        repeat (6) @(posedge axi_aclk);

        // Write bank 0 row 1 col 0
        s_axi_awid    = 4'h2;
        s_axi_awaddr  = mc_addr(3'd0, 14'd1, 10'd0);
        s_axi_wdata   = 64'hCAFE0000_0000BEEF;
        s_axi_wstrb   = 8'hFF;
        s_axi_wlast   = 1'b1;
        s_axi_awvalid = 1'b1;
        s_axi_wvalid  = 1'b1;
        @(posedge axi_aclk);
        while (!(s_axi_awready && s_axi_wready))
            @(posedge axi_aclk);
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;

        while (!s_axi_bvalid)
            @(posedge axi_aclk);
        if (s_axi_bid !== 4'h2 || s_axi_bresp !== 2'b00) begin
            $display("FAIL smoke: B mismatch");
            err = err + 1;
        end
        s_axi_bready = 1'b1;
        @(posedge axi_aclk);
        s_axi_bready = 1'b0;

        repeat (40) @(posedge dfi_clk);

        // Read same location
        rd_q[rd_wr[1:0]] = mc_addr(3'd0, 14'd1, 10'd0);
        rd_wr = rd_wr + 1;
        s_axi_arid    = 4'h3;
        s_axi_araddr  = mc_addr(3'd0, 14'd1, 10'd0);
        s_axi_arvalid = 1'b1;
        @(posedge axi_aclk);
        while (!s_axi_arready)
            @(posedge axi_aclk);
        s_axi_arvalid = 1'b0;

        while (!s_axi_rvalid)
            @(posedge axi_aclk);
        if (s_axi_rid !== 4'h3 || s_axi_rresp !== 2'b00 || !s_axi_rlast) begin
            $display("FAIL smoke: R meta mismatch");
            err = err + 1;
        end
        smoke_ra = mc_addr(3'd0, 14'd1, 10'd0);
        if (s_axi_rdata !== {32'hA5A5A5A5, 14'h0, smoke_ra[DFI_ADDR_WIDTH-1:0]}) begin
            $display("FAIL smoke: RDATA mismatch");
            err = err + 1;
        end
        s_axi_rready = 1'b1;
        @(posedge axi_aclk);
        s_axi_rready = 1'b0;

        if (err == 0)
            $display("PASS: tb_param_smoke (CDC_FIFO_DEPTH=16)");
        else
            $display("FAIL: tb_param_smoke err=%0d", err);
        $finish;
    end

endmodule
