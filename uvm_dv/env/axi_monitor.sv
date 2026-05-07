// AXI4 passive monitor.
// Observes the AXI interface handshakes and emits completed axi_seq_item
// objects via the ap analysis port for the scoreboard and coverage collector.
// Separate threads watch AW, W, B, AR, and R channels concurrently.
class axi_monitor #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends uvm_monitor;

    `uvm_component_param_utils(axi_monitor #(ADDR_W, DATA_W, ID_W))

    typedef axi_seq_item #(ADDR_W, DATA_W, ID_W) item_t;

    virtual axi4_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)) vif;

    // Completed write transactions (after B handshake).
    uvm_analysis_port #(item_t) wr_ap;
    // Completed read transactions (after final R beat).
    uvm_analysis_port #(item_t) rd_ap;

    // Pending write table: AW items waiting for their W beats + B response.
    item_t aw_pending[$];

    // Pending W beats: collected independently and matched to aw_pending by order.
    // AXI4 allows W to arrive before or after AW; we buffer both sides.
    typedef struct { logic [DATA_W-1:0] data; logic [DATA_W/8-1:0] strb; } w_beat_t;
    w_beat_t w_beats[$];  // all observed W beats in order

    // Pending read table — keyed on arid.
    item_t ar_pending[$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        wr_ap = new("wr_ap", this);
        rd_ap = new("rd_ap", this);
        if (!uvm_config_db #(virtual axi4_if #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W)))::get(
                this, "", "axi_vif", vif))
            `uvm_fatal("CFG", "axi_vif not set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            collect_aw();
            collect_w();
            collect_b();
            collect_ar();
            collect_r();
        join
    endtask

    // Capture AW handshakes and push to aw_pending.
    task collect_aw();
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.awvalid && vif.monitor_cb.awready) begin
                item_t it = item_t::type_id::create("aw_item");
                it.op    = AXI_WRITE;
                it.id    = vif.monitor_cb.awid;
                it.addr  = vif.monitor_cb.awaddr;
                it.len   = vif.monitor_cb.awlen;
                it.size  = vif.monitor_cb.awsize;
                it.burst = vif.monitor_cb.awburst;
                it.data  = new[int'(it.len)+1];
                it.strb  = new[int'(it.len)+1];
                aw_pending.push_back(it);
            end
        end
    endtask

    // Collect W beats independently and match them to aw_pending in order.
    task collect_w();
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.wvalid && vif.monitor_cb.wready) begin
                w_beat_t beat;
                beat.data = vif.monitor_cb.wdata;
                beat.strb = vif.monitor_cb.wstrb;
                w_beats.push_back(beat);
                // Try to fill the oldest aw_pending that still has unfilled beats.
                foreach (aw_pending[i]) begin
                    item_t it = aw_pending[i];
                    if (it._beat_cnt <= int'(it.len) && w_beats.size() > 0) begin
                        w_beat_t b = w_beats.pop_front();
                        it.data[it._beat_cnt] = b.data;
                        it.strb[it._beat_cnt] = b.strb;
                        it._beat_cnt++;
                        break;
                    end
                end
            end
        end
    endtask

    // Capture B responses and pair with earliest matching aw_pending entry.
    // W beats may still be arriving concurrently; we emit the item when B fires
    // regardless (scoreboard only checks bresp for writes, not wdata).
    task collect_b();
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.bvalid && vif.monitor_cb.bready) begin
                item_t it = null;
                foreach (aw_pending[i]) begin
                    if (aw_pending[i].id == vif.monitor_cb.bid) begin
                        it = aw_pending[i];
                        aw_pending.delete(i);
                        break;
                    end
                end
                if (it == null)
                    `uvm_error("MON", $sformatf(
                        "B resp BID=%0h at %0t with no matching AW", vif.monitor_cb.bid, $time))
                else begin
                    it.got_id   = vif.monitor_cb.bid;
                    it.got_resp = vif.monitor_cb.bresp;
                    wr_ap.write(it);
                end
            end
        end
    endtask

    // Capture AR handshakes and create pending read items.
    task collect_ar();
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.arvalid && vif.monitor_cb.arready) begin
                item_t it = item_t::type_id::create("ar_item");
                it.op        = AXI_READ;
                it.id        = vif.monitor_cb.arid;
                it.addr      = vif.monitor_cb.araddr;
                it.len       = vif.monitor_cb.arlen;
                it.size      = vif.monitor_cb.arsize;
                it.burst     = vif.monitor_cb.arburst;
                it.got_rdata = new[int'(it.len)+1];
                it._beat_cnt = 0;
                ar_pending.push_back(it);
            end
        end
    endtask

    // Capture R beats and complete transactions on rlast.
    task collect_r();
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.rvalid && vif.monitor_cb.rready) begin
                item_t it = null;
                // Find the oldest pending AR with matching ID.
                foreach (ar_pending[i]) begin
                    if (ar_pending[i].id == vif.monitor_cb.rid) begin
                        it = ar_pending[i];
                        break;
                    end
                end
                if (it == null) begin
                    `uvm_error("MON", $sformatf(
                        "R beat RID=%0h at %0t with no matching AR", vif.monitor_cb.rid, $time))
                end else begin
                    it.got_rdata[it._beat_cnt] = vif.monitor_cb.rdata;
                    it._beat_cnt++;
                    if (vif.monitor_cb.rlast) begin
                        it.got_resp = vif.monitor_cb.rresp;
                        it.got_id   = vif.monitor_cb.rid;
                        foreach (ar_pending[i]) begin
                            if (ar_pending[i] == it) begin
                                ar_pending.delete(i);
                                break;
                            end
                        end
                        rd_ap.write(it);
                    end
                end
            end
        end
    endtask

endclass
