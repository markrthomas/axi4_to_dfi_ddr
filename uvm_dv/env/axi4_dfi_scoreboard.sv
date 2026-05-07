// Scoreboard for the AXI4-to-DFI bridge.
//
// Checks:
//   Write completions: bresp matches exp_resp.
//   Read completions:  rresp matches exp_resp AND each rdata beat matches
//                      expected_rdata(beat_addr) from the PHY model formula.
//
// The PHY data formula is: rdata = {32'hA5A5A5A5, 14'h0, addr[DFI_ADDR_W-1:0]}
// This must match the tb_top PHY model and is parameterised via DFI_ADDR_W.
class axi4_dfi_scoreboard #(
    parameter int ADDR_W     = 32,
    parameter int DATA_W     = 64,
    parameter int ID_W       = 4,
    parameter int DFI_ADDR_W = 18    // bits of addr embedded in rdata
) extends uvm_scoreboard;

    `uvm_component_param_utils(axi4_dfi_scoreboard #(ADDR_W, DATA_W, ID_W, DFI_ADDR_W))

    typedef axi_seq_item #(ADDR_W, DATA_W, ID_W) item_t;

    uvm_analysis_imp_wr #(item_t, axi4_dfi_scoreboard #(ADDR_W,DATA_W,ID_W,DFI_ADDR_W)) wr_imp;
    uvm_analysis_imp_rd #(item_t, axi4_dfi_scoreboard #(ADDR_W,DATA_W,ID_W,DFI_ADDR_W)) rd_imp;

    int unsigned pass_cnt;
    int unsigned fail_cnt;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        wr_imp = new("wr_imp", this);
        rd_imp = new("rd_imp", this);
        pass_cnt = 0;
        fail_cnt = 0;
    endfunction

    // Called by wr_ap analysis port for every completed write transaction.
    function void write_wr(item_t it);
        if (it.got_resp !== it.exp_resp) begin
            `uvm_error("SB", $sformatf(
                "WRITE RESP mismatch: ID=%0h addr=%08h exp_resp=%02b got_resp=%02b",
                it.id, it.addr, it.exp_resp, it.got_resp))
            fail_cnt++;
        end else begin
            `uvm_info("SB", $sformatf(
                "WRITE OK: ID=%0h addr=%08h bresp=%02b", it.id, it.addr, it.got_resp),
                UVM_HIGH)
            pass_cnt++;
        end
    endfunction

    // Called by rd_ap analysis port for every completed read transaction.
    function void write_rd(item_t it);
        logic [DATA_W-1:0] exp_d;
        logic [ADDR_W-1:0] beat_addr;
        int beat_bytes = DATA_W / 8;

        if (it.got_resp !== it.exp_resp) begin
            `uvm_error("SB", $sformatf(
                "READ RESP mismatch: ID=%0h addr=%08h exp_resp=%02b got_resp=%02b",
                it.id, it.addr, it.exp_resp, it.got_resp))
            fail_cnt++;
        end

        // Only check rdata on OKAY responses (SLVERR data is undefined).
        if (it.exp_resp == 2'b00) begin
            for (int k = 0; k <= int'(it.len); k++) begin
                beat_addr = it.addr + logic'(k * beat_bytes);
                exp_d     = expected_rdata(beat_addr);
                if (it.got_rdata[k] !== exp_d) begin
                    `uvm_error("SB", $sformatf(
                        "READ DATA mismatch beat %0d: ID=%0h addr=%08h exp=%016h got=%016h",
                        k, it.id, beat_addr, exp_d, it.got_rdata[k]))
                    fail_cnt++;
                end else begin
                    `uvm_info("SB", $sformatf(
                        "READ OK beat %0d: ID=%0h addr=%08h data=%016h",
                        k, it.id, beat_addr, it.got_rdata[k]), UVM_HIGH)
                    pass_cnt++;
                end
            end
        end
    endfunction

    // PHY model data formula — must match tb_top always block.
    function automatic logic [DATA_W-1:0] expected_rdata(logic [ADDR_W-1:0] addr);
        return {32'hA5A5A5A5, 14'h0, addr[DFI_ADDR_W-1:0]};
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SB", $sformatf("Scoreboard: %0d checks PASSED, %0d FAILED",
                  pass_cnt, fail_cnt), UVM_NONE)
        if (fail_cnt > 0)
            `uvm_error("SB", "*** SCOREBOARD FAILURES DETECTED ***")
    endfunction

endclass
