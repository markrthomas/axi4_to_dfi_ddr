// DFI passive monitor.
// Decodes SDRAM commands and emits dfi_seq_item via cmd_ap.
// Also maintains running counters (reset via reset_counts()) used by
// mc_cmd_test to check PRE/ACT/RDCAS/WRCAS ratios for specific scenarios.
class dfi_monitor #(
    parameter int ADDR_W = 18,
    parameter int BANK_W = 3
) extends uvm_monitor;

    `uvm_component_param_utils(dfi_monitor #(ADDR_W, BANK_W))

    typedef dfi_seq_item #(ADDR_W, BANK_W) item_t;

    virtual dfi_if #(.ADDR_W(ADDR_W), .BANK_W(BANK_W)) vif;

    uvm_analysis_port #(item_t) cmd_ap;

    // Running totals since last reset_counts().
    int unsigned cnt_pre;
    int unsigned cnt_act;
    int unsigned cnt_rdcas;
    int unsigned cnt_wrcas;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cmd_ap = new("cmd_ap", this);
        if (!uvm_config_db #(virtual dfi_if #(.ADDR_W(ADDR_W),.BANK_W(BANK_W)))::get(
                this, "", "dfi_vif", vif))
            `uvm_fatal("CFG", "dfi_vif not set in config_db")
    endfunction

    function void reset_counts();
        cnt_pre   = 0;
        cnt_act   = 0;
        cnt_rdcas = 0;
        cnt_wrcas = 0;
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(vif.monitor_cb);
            // Only count commands after init_complete, chip selected, and monitor enabled.
            if (vif.monitor_cb.init_complete && !vif.monitor_cb.cs_n[0]) begin
                item_t it;
                dfi_cmd_e cmd = decode_cmd(vif.monitor_cb.ras_n,
                                           vif.monitor_cb.cas_n,
                                           vif.monitor_cb.we_n);
                if (cmd != DFI_CMD_NOP) begin
                    it           = item_t::type_id::create("dfi_cmd");
                    it.cmd       = cmd;
                    it.address   = vif.monitor_cb.address;
                    it.bank      = vif.monitor_cb.bank;
                    it.timestamp = $time;
                    cmd_ap.write(it);
                    case (cmd)
                        DFI_CMD_PRE:   cnt_pre++;
                        DFI_CMD_ACT:   cnt_act++;
                        DFI_CMD_RDCAS: cnt_rdcas++;
                        DFI_CMD_WRCAS: cnt_wrcas++;
                        default: ;
                    endcase
                end
            end
        end
    endtask

    // Decode RAS#/CAS#/WE# to SDRAM command (matches existing tb logic).
    function dfi_cmd_e decode_cmd(logic ras_n, logic cas_n, logic we_n);
        if (!ras_n &&  cas_n && !we_n) return DFI_CMD_PRE;
        if (!ras_n &&  cas_n &&  we_n) return DFI_CMD_ACT;
        if ( ras_n && !cas_n &&  we_n) return DFI_CMD_RDCAS;
        if ( ras_n && !cas_n && !we_n) return DFI_CMD_WRCAS;
        return DFI_CMD_NOP;
    endfunction

endclass
