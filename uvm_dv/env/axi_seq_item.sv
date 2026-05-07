// AXI4 transaction item — covers both write and read ops.
// The driver reads the request fields; the monitor fills in response fields.
// The scoreboard compares resp / rdata against exp_resp / exp_rdata.

typedef enum logic { AXI_WRITE, AXI_READ } axi_op_e;

// Write-channel ordering mode (mirrors the three testbench task variants).
typedef enum { WR_SIMUL, WR_AW_FIRST, WR_W_FIRST } wr_order_e;

class axi_seq_item #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W   = 4
) extends uvm_sequence_item;

    `uvm_object_param_utils_begin(axi_seq_item #(ADDR_W, DATA_W, ID_W))
        `uvm_field_enum(axi_op_e,    op,       UVM_ALL_ON)
        `uvm_field_int (id,                     UVM_ALL_ON)
        `uvm_field_int (addr,                   UVM_ALL_ON)
        `uvm_field_int (len,                    UVM_ALL_ON)
        `uvm_field_int (size,                   UVM_ALL_ON)
        `uvm_field_int (burst,                  UVM_ALL_ON)
        `uvm_field_array_int(data,              UVM_ALL_ON)
        `uvm_field_array_int(strb,              UVM_ALL_ON)
        `uvm_field_int (exp_resp,               UVM_ALL_ON)
        `uvm_field_array_int(exp_rdata,         UVM_ALL_ON)
        `uvm_field_enum(wr_order_e, wr_order,  UVM_ALL_ON)
        `uvm_field_int (bready_delay,           UVM_ALL_ON)
        `uvm_field_int (rready_delay,           UVM_ALL_ON)
    `uvm_object_utils_end

    // Request fields
    rand axi_op_e             op;
    rand logic [ID_W-1:0]     id;
    rand logic [ADDR_W-1:0]   addr;
    rand logic [7:0]          len;      // burst length encoding (beats - 1)
    rand logic [2:0]          size;     // 3 = 8-byte beats (full 64-bit width)
    rand logic [1:0]          burst;    // 2'b01 = INCR
    // Optional sideband (not randomised by default; zero is legal for this DUT)
    logic                     lock;
    logic [3:0]               cache;
    logic [2:0]               prot;
    logic [3:0]               qos;
    logic [3:0]               region;

    // Write data payload — sized by len in pre_randomize / set by sequence
    rand logic [DATA_W-1:0]   data[];
    rand logic [DATA_W/8-1:0] strb[];

    // Expected response — filled by sequence before item is sent
    logic [1:0]               exp_resp;       // 2'b00 OKAY, 2'b10 SLVERR
    logic [DATA_W-1:0]        exp_rdata[];    // one entry per R beat

    // Driver behaviour knobs
    wr_order_e                wr_order;       // default WR_SIMUL
    int unsigned              bready_delay;   // cycles to hold bready low after bvalid
    int unsigned              rready_delay;   // cycles to hold rready low after rvalid

    // Response fields — filled by monitor after transaction completes
    logic [ID_W-1:0]          got_id;
    logic [1:0]               got_resp;
    logic [DATA_W-1:0]        got_rdata[];
    // Internal monitor beat counter (not part of public API).
    int                       _beat_cnt;

    // Legal defaults
    constraint size_legal_c  { size  == 3'd3;  }
    constraint burst_legal_c { burst == 2'b01; }
    constraint len_range_c   { len   inside {[0:3]}; }
    constraint data_size_c   {
        data.size() == int'(len) + 1;
        strb.size() == int'(len) + 1;
    }
    constraint strb_full_c   { foreach (strb[i]) strb[i] == '1; }

    function new(string name = "axi_seq_item");
        super.new(name);
        lock     = 1'b0;
        cache    = 4'b0;
        prot     = 3'b0;
        qos      = 4'b0;
        region   = 4'b0;
        exp_resp = 2'b00;
        wr_order     = WR_SIMUL;
        bready_delay = 0;
        rready_delay = 0;
    endfunction

endclass
