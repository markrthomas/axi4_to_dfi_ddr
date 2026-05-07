// DFI command item emitted by the DFI monitor.
// Represents one SDRAM command decoded from the DFI bus.
typedef enum {
    DFI_CMD_NOP,
    DFI_CMD_PRE,    // Precharge: !ras_n && cas_n  && !we_n
    DFI_CMD_ACT,    // Activate:  !ras_n && cas_n  &&  we_n
    DFI_CMD_RDCAS,  // Read CAS:   ras_n && !cas_n &&  we_n
    DFI_CMD_WRCAS   // Write CAS:  ras_n && !cas_n && !we_n
} dfi_cmd_e;

class dfi_seq_item #(
    parameter int ADDR_W = 18,
    parameter int BANK_W = 3
) extends uvm_sequence_item;

    `uvm_object_param_utils_begin(dfi_seq_item #(ADDR_W, BANK_W))
        `uvm_field_enum(dfi_cmd_e,    cmd,     UVM_ALL_ON)
        `uvm_field_int (address,               UVM_ALL_ON)
        `uvm_field_int (bank,                  UVM_ALL_ON)
        `uvm_field_time(timestamp,             UVM_ALL_ON)
    `uvm_object_utils_end

    dfi_cmd_e              cmd;
    logic [ADDR_W-1:0]     address;
    logic [BANK_W-1:0]     bank;
    time                   timestamp;

    function new(string name = "dfi_seq_item");
        super.new(name);
    endfunction

endclass
