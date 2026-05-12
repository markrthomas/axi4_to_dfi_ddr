// Verilator coverage harness for axi4_to_dfi_bridge (dual-clock: axi_aclk=20ns, dfi_clk=14ns).
// Exercises: reset sequence, single-beat write, single-beat read, 4-beat burst write.
#include "Vaxi4_to_dfi_bridge.h"
#include "verilated.h"
#if VM_COVERAGE
#include "verilated_cov.h"
#endif
#include <cstdint>
#include <cstring>

static uint64_t g_time_ns = 0;
double sc_time_stamp() { return (double)g_time_ns; }

static Vaxi4_to_dfi_bridge* top;

// DFI PHY model: MC_CL=6 cycle latency on dfi_rddata_en → dfi_rddata_valid.
static const int MC_CL = 6;
static uint8_t  rddata_en_sr[16] = {0};  // shift register

static void dfi_phy_model() {
    // Shift and delay dfi_rddata_en by MC_CL dfi_clk cycles.
    for (int i = MC_CL; i > 0; i--) rddata_en_sr[i] = rddata_en_sr[i - 1];
    rddata_en_sr[0] = top->dfi_rddata_en;

    top->dfi_rddata_valid = rddata_en_sr[MC_CL - 1];
    top->dfi_rddata       = (uint64_t)0xA5A5A5A5A5A5A5A5ULL;
    top->dfi_ctrlupd_ack  = top->dfi_ctrlupd_req;
    top->dfi_phyupd_req   = 0;
    top->dfi_lp_ctrl_ack  = 0;
}

// Simulation step: advance 1ns, toggle clocks, eval.
// axi_aclk period = 20ns (half = 10ns), dfi_clk period = 14ns (half = 7ns).
static bool prev_axi = 0, prev_dfi = 0;

static void step() {
    uint8_t new_axi = (g_time_ns / 10) % 2;
    uint8_t new_dfi = (g_time_ns / 7)  % 2;

    // Fire DFI PHY model on each dfi_clk rising edge.
    if (!prev_dfi && new_dfi) dfi_phy_model();

    top->axi_aclk = new_axi;
    top->dfi_clk  = new_dfi;
    top->eval();

    prev_axi = new_axi;
    prev_dfi = new_dfi;
    ++g_time_ns;
}

// Advance until N axi_aclk rising edges have occurred.
static void axi_ticks(int n) {
    int edges = 0;
    while (edges < n) {
        bool was = top->axi_aclk;
        step();
        if (!was && top->axi_aclk) edges++;
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vaxi4_to_dfi_bridge;

    // Initialize all inputs to safe defaults.
    top->axi_aclk     = 0;
    top->axi_aresetn  = 0;
    top->dfi_clk      = 0;
    top->dfi_rst_n    = 0;
    top->dfi_init_complete = 0;
    top->dfi_rddata        = 0;
    top->dfi_rddata_valid  = 0;
    top->dfi_ctrlupd_ack   = 0;
    top->dfi_phyupd_req    = 0;
    top->dfi_lp_ctrl_ack   = 0;
    top->s_axi_awvalid = 0; top->s_axi_wvalid = 0; top->s_axi_bready = 0;
    top->s_axi_arvalid = 0; top->s_axi_rready = 0;
    // Tie off optional AXI sideband fields.
    top->s_axi_awlock = 0; top->s_axi_awcache = 0; top->s_axi_awqos = 0;
    top->s_axi_awregion = 0; top->s_axi_awuser = 0; top->s_axi_wuser = 0;
    top->s_axi_arlock = 0; top->s_axi_arcache = 0; top->s_axi_arqos = 0;
    top->s_axi_arregion = 0; top->s_axi_aruser = 0;
    top->eval();

    // Reset sequence: hold both resets for 20 axi_aclk cycles.
    axi_ticks(20);
    // Release DFI reset first; assert dfi_init_complete.
    top->dfi_rst_n         = 1;
    top->dfi_init_complete = 1;
    axi_ticks(10);
    // Release AXI reset.
    top->axi_aresetn = 1;
    axi_ticks(5);

    // --- Transaction 1: single-beat write (AWLEN=0, AWSIZE=3, INCR) ---
    top->s_axi_awvalid = 1;
    top->s_axi_awid    = 0;
    top->s_axi_awaddr  = 0x00001000;
    top->s_axi_awlen   = 0;
    top->s_axi_awsize  = 3;
    top->s_axi_awburst = 1;
    top->s_axi_awprot  = 0;
    top->s_axi_wvalid  = 1;
    top->s_axi_wdata   = (uint64_t)0xCAFEBABEDEAD0001ULL;
    top->s_axi_wstrb   = 0xFF;
    top->s_axi_wlast   = 1;
    top->s_axi_bready  = 1;

    // Wait for AW + W handshake.
    for (int i = 0; i < 200; i++) {
        bool was_axi = top->axi_aclk;
        step();
        if (!was_axi && top->axi_aclk) {
            if (top->s_axi_awvalid && top->s_axi_awready) top->s_axi_awvalid = 0;
            if (top->s_axi_wvalid  && top->s_axi_wready)  top->s_axi_wvalid  = 0;
            if (!top->s_axi_awvalid && !top->s_axi_wvalid) break;
        }
    }
    // Wait for B response.
    for (int i = 0; i < 400; i++) {
        bool was_axi = top->axi_aclk;
        step();
        if (!was_axi && top->axi_aclk && top->s_axi_bvalid && top->s_axi_bready) break;
    }
    top->s_axi_bready = 0;
    axi_ticks(5);

    // --- Transaction 2: single-beat read (ARLEN=0) ---
    top->s_axi_arvalid = 1;
    top->s_axi_arid    = 1;
    top->s_axi_araddr  = 0x00002000;
    top->s_axi_arlen   = 0;
    top->s_axi_arsize  = 3;
    top->s_axi_arburst = 1;
    top->s_axi_arprot  = 0;
    top->s_axi_rready  = 1;

    // Wait for AR handshake.
    for (int i = 0; i < 200; i++) {
        bool was_axi = top->axi_aclk;
        step();
        if (!was_axi && top->axi_aclk && top->s_axi_arvalid && top->s_axi_arready) {
            top->s_axi_arvalid = 0; break;
        }
    }
    // Wait for R response.
    for (int i = 0; i < 400; i++) {
        bool was_axi = top->axi_aclk;
        step();
        if (!was_axi && top->axi_aclk && top->s_axi_rvalid && top->s_axi_rready) break;
    }
    top->s_axi_rready = 0;
    axi_ticks(5);

    // --- Transaction 3: 4-beat burst write (AWLEN=3) ---
    top->s_axi_awvalid = 1;
    top->s_axi_awid    = 2;
    top->s_axi_awaddr  = 0x00004000;
    top->s_axi_awlen   = 3;
    top->s_axi_awsize  = 3;
    top->s_axi_awburst = 1;
    top->s_axi_awprot  = 0;
    top->s_axi_bready  = 1;

    for (int i = 0; i < 200; i++) {
        bool was_axi = top->axi_aclk;
        step();
        if (!was_axi && top->axi_aclk && top->s_axi_awvalid && top->s_axi_awready) {
            top->s_axi_awvalid = 0; break;
        }
    }
    // Drive 4 W beats.
    for (int beat = 0; beat < 4; beat++) {
        top->s_axi_wvalid = 1;
        top->s_axi_wdata  = (uint64_t)0xA0A0A0A000000000ULL + beat;
        top->s_axi_wstrb  = 0xFF;
        top->s_axi_wlast  = (beat == 3) ? 1 : 0;
        for (int i = 0; i < 200; i++) {
            bool was_axi = top->axi_aclk;
            step();
            if (!was_axi && top->axi_aclk && top->s_axi_wvalid && top->s_axi_wready) {
                top->s_axi_wvalid = 0; break;
            }
        }
    }
    // Wait for B.
    for (int i = 0; i < 400; i++) {
        bool was_axi = top->axi_aclk;
        step();
        if (!was_axi && top->axi_aclk && top->s_axi_bvalid && top->s_axi_bready) break;
    }
    top->s_axi_bready = 0;

    // Settle.
    axi_ticks(30);

#if VM_COVERAGE
    VerilatedCov::write("coverage.dat");
#endif
    delete top;
    return 0;
}
