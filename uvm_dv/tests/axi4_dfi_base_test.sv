// Base test — builds the env, manages phase objection.
// All concrete tests extend this and override run_phase.
class axi4_dfi_base_test extends uvm_test;

    `uvm_component_utils(axi4_dfi_base_test)

    // Use default DUT parameters (matching the tb_top instantiation).
    localparam int ADDR_W     = 32;
    localparam int DATA_W     = 64;
    localparam int ID_W       = 4;
    localparam int DFI_ADDR_W = 18;
    localparam int DFI_BANK_W = 3;

    axi4_dfi_env #(ADDR_W, DATA_W, ID_W, DFI_ADDR_W, DFI_BANK_W) env;

    // Simulation timeout in ns; tests can override.
    int unsigned timeout_ns = 300_000_000;  // 300 ms = 300_000_000 ns

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi4_dfi_env #(ADDR_W,DATA_W,ID_W,DFI_ADDR_W,DFI_BANK_W)::type_id::create("env",this);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        #timeout_ns;
        `uvm_fatal("TIMEOUT", $sformatf("Test timed out after %0d ns", timeout_ns))
        phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
        uvm_report_server srv = uvm_report_server::get_server();
        if (srv.get_severity_count(UVM_FATAL) > 0 ||
            srv.get_severity_count(UVM_ERROR) > 0)
            `uvm_info("TEST", "*** FAIL ***", UVM_NONE)
        else
            `uvm_info("TEST", "*** PASS ***", UVM_NONE)
    endfunction

endclass
