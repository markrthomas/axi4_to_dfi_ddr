// Functional coverage for AXI4-to-DFI bridge.
// Subscribes to both AXI write and read analysis ports.
class axi4_dfi_coverage #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends uvm_subscriber #(axi_seq_item #(ADDR_W, DATA_W, ID_W));

    `uvm_component_param_utils(axi4_dfi_coverage #(ADDR_W, DATA_W, ID_W))

    typedef axi_seq_item #(ADDR_W, DATA_W, ID_W) item_t;

    // Second analysis port for read completions.
    uvm_analysis_imp_rd #(item_t, axi4_dfi_coverage #(ADDR_W,DATA_W,ID_W)) rd_imp;

    item_t  cur_item;

    covergroup axi_wr_cg;
        cp_burst: coverpoint cur_item.burst {
            bins incr  = {2'b01};
            bins fixed = {2'b00};
            bins wrap  = {2'b10};
        }
        cp_len: coverpoint cur_item.len {
            bins single = {0};
            bins burst2 = {1};
            bins burst4 = {3};
            bins other  = {[2:2]};
        }
        cp_resp: coverpoint cur_item.got_resp {
            bins okay   = {2'b00};
            bins slverr = {2'b10};
            bins other  = {[1:1], [3:3]};
        }
        cx_len_resp: cross cp_len, cp_resp;
    endgroup

    covergroup axi_rd_cg;
        cp_burst: coverpoint cur_item.burst {
            bins incr  = {2'b01};
            bins other = default;
        }
        cp_len: coverpoint cur_item.len {
            bins single = {0};
            bins burst4 = {3};
            bins other  = {[1:2]};
        }
        cp_resp: coverpoint cur_item.got_resp {
            bins okay   = {2'b00};
            bins slverr = {2'b10};
        }
        cx_len_resp: cross cp_len, cp_resp;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        axi_wr_cg = new();
        axi_rd_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        rd_imp = new("rd_imp", this);
    endfunction

    // Called by the base uvm_subscriber for write completions.
    function void write(item_t t);
        cur_item = t;
        axi_wr_cg.sample();
    endfunction

    // Called by rd_imp for read completions.
    function void write_rd(item_t t);
        cur_item = t;
        axi_rd_cg.sample();
    endfunction

endclass
