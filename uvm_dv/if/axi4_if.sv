// AXI4 slave interface — driver (master-side) and monitor clocking blocks.
interface axi4_if #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4,
    parameter int USER_W = 1
) (
    input logic aclk,
    input logic aresetn
);
    // AW channel
    logic [ID_W-1:0]     awid;
    logic [ADDR_W-1:0]   awaddr;
    logic [7:0]          awlen;
    logic [2:0]          awsize;
    logic [1:0]          awburst;
    logic                awlock;
    logic [3:0]          awcache;
    logic [2:0]          awprot;
    logic [3:0]          awqos;
    logic [3:0]          awregion;
    logic [USER_W-1:0]   awuser;
    logic                awvalid;
    logic                awready;

    // W channel
    logic [DATA_W-1:0]   wdata;
    logic [DATA_W/8-1:0] wstrb;
    logic                wlast;
    logic [USER_W-1:0]   wuser;
    logic                wvalid;
    logic                wready;

    // B channel
    logic [ID_W-1:0]     bid;
    logic [1:0]          bresp;
    logic [USER_W-1:0]   buser;
    logic                bvalid;
    logic                bready;

    // AR channel
    logic [ID_W-1:0]     arid;
    logic [ADDR_W-1:0]   araddr;
    logic [7:0]          arlen;
    logic [2:0]          arsize;
    logic [1:0]          arburst;
    logic                arlock;
    logic [3:0]          arcache;
    logic [2:0]          arprot;
    logic [3:0]          arqos;
    logic [3:0]          arregion;
    logic [USER_W-1:0]   aruser;
    logic                arvalid;
    logic                arready;

    // R channel
    logic [ID_W-1:0]     rid;
    logic [DATA_W-1:0]   rdata;
    logic [1:0]          rresp;
    logic                rlast;
    logic [USER_W-1:0]   ruser;
    logic                rvalid;
    logic                rready;

    // Driver drives master-side signals, samples slave-side.
    clocking driver_cb @(posedge aclk);
        default input #1step output #1;
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot,
               awqos, awregion, awuser, awvalid;
        output wdata, wstrb, wlast, wuser, wvalid;
        output bready;
        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot,
               arqos, arregion, aruser, arvalid;
        output rready;
        input  awready, wready;
        input  bid, bresp, buser, bvalid;
        input  arready;
        input  rid, rdata, rresp, rlast, ruser, rvalid;
    endclocking

    // Monitor samples all signals with 1-step skew to avoid race with edge.
    clocking monitor_cb @(posedge aclk);
        default input #1step;
        input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot,
              awqos, awregion, awuser, awvalid, awready;
        input wdata, wstrb, wlast, wuser, wvalid, wready;
        input bid, bresp, buser, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot,
              arqos, arregion, aruser, arvalid, arready;
        input rid, rdata, rresp, rlast, ruser, rvalid, rready;
    endclocking

    modport driver_mp  (clocking driver_cb,  input aclk, aresetn);
    modport monitor_mp (clocking monitor_cb, input aclk, aresetn);
endinterface
