# axi_dfi.sdc — timing constraints for axi4_to_dfi_bridge (AXI4 -> DFI/DDR).
# T0/T2 collateral (tapeout-readiness program). Run on OpenSTA (pathfind) or
# PrimeTime (sign-off) against a target liberty — neither exists in this workspace.
#
# TWO asynchronous clock domains (unlike the single-clock siblings): the AXI side
# (axi_aclk/axi_aresetn) and the DFI/DRAM side (dfi_clk/dfi_rst_n). All crossings go
# through async_fifo_gray / cdc_sync (proven by `make cdc`), so the two clocks are a
# false-path (asynchronous) group — NOT timed against each other.

set AXI_PERIOD 2.5 ;# 400 MHz placeholder
set DFI_PERIOD 1.25 ;# 800 MHz placeholder (DFI typically runs faster)
create_clock -name axi_aclk -period $AXI_PERIOD [get_ports axi_aclk]
create_clock -name dfi_clk  -period $DFI_PERIOD [get_ports dfi_clk]

# The two domains are asynchronous — cut timing between them (the CDC synchronizers
# handle metastability; `make cdc` proves no crossing bypasses one).
set_clock_groups -asynchronous -group {axi_aclk} -group {dfi_clk}

# Asynchronous active-low resets: not setup/hold timing paths.
set_false_path -from [get_ports axi_aresetn]
set_false_path -from [get_ports dfi_rst_n]

# I/O budgets (40% in / 40% out), each relative to its own domain clock.
set_input_delay  -clock axi_aclk [expr {0.40*$AXI_PERIOD}] [remove_from_collection [all_inputs] [get_ports {axi_aclk axi_aresetn dfi_clk dfi_rst_n}]]
set_output_delay -clock axi_aclk [expr {0.40*$AXI_PERIOD}] [all_outputs]
# (Split outputs per true launch domain at integration; single group shown here.)
