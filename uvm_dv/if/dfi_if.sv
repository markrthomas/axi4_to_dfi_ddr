// DFI PHY interface — passive monitor only (DUT drives all command/data outputs).
interface dfi_if #(
    parameter int ADDR_W = 18,
    parameter int BANK_W = 3,
    parameter int DATA_W = 64,
    parameter int MASK_W = 8,
    parameter int CS_W   = 1,
    parameter int ODT_W  = 1,
    parameter int CKE_W  = 1
) (
    input logic clk,
    input logic rst_n
);
    // Command bus (DUT → PHY)
    logic [ADDR_W-1:0] address;
    logic [BANK_W-1:0] bank;
    logic              ras_n;
    logic              cas_n;
    logic              we_n;
    logic [CS_W-1:0]   cs_n;
    logic [ODT_W-1:0]  odt;
    logic [CKE_W-1:0]  cke;
    logic              act_n;

    // Write data (DUT → PHY)
    logic [DATA_W-1:0] wrdata;
    logic [MASK_W-1:0] wrdata_mask;
    logic              wrdata_en;

    // Read data (PHY → DUT) — driven by tb_top PHY model
    logic [DATA_W-1:0] rddata;
    logic              rddata_valid;
    logic              rddata_en;   // DUT asserts to request read data

    // Sideband
    logic              init_start;
    logic              init_complete;
    logic              ctrlupd_req;
    logic              ctrlupd_ack;
    logic              phyupd_req;
    logic              phyupd_ack;
    logic              lp_ctrl_req;
    logic              lp_ctrl_ack;

    clocking monitor_cb @(posedge clk);
        default input #1step;
        input address, bank, ras_n, cas_n, we_n, cs_n, odt, cke, act_n;
        input wrdata, wrdata_mask, wrdata_en;
        input rddata, rddata_valid, rddata_en;
        input init_start, init_complete;
        input ctrlupd_req, ctrlupd_ack, phyupd_req, phyupd_ack;
        input lp_ctrl_req, lp_ctrl_ack;
    endclocking

    modport monitor_mp (clocking monitor_cb, input clk, rst_n);
endinterface
