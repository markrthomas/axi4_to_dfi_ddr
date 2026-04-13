# Example SDC fragment for axi4_to_dfi_bridge (integrator-owned).
# Replace clock names/periods with your SoC definitions. This file is not
# consumed by syn/yosys.ys (Yosys uses native commands); it is for ASIC/FPGA
# flows that accept Synopsys-style SDC.
#
# create_clock -name axi_aclk -period 10.0 [get_ports axi_aclk]
# create_clock -name dfi_clk  -period 2.5  [get_ports dfi_clk]
#
# Gray FIFO pointers cross between domains: false-path the synchronized
# Gray buses and any single-bit control you treat as slow/async.
# set_false_path -from [get_clocks axi_aclk] -to [get_clocks dfi_clk]
# set_false_path -from [get_clocks dfi_clk]  -to [get_clocks axi_aclk]
#
# For tighter CDC signoff, use clock groups or explicit set_max_delay on
# synchronizer chains instead of blanket false paths.
