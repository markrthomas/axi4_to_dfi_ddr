# opensta.tcl — STA driver for axi4_to_dfi_bridge (T2 collateral; not run here:
# no OpenSTA/liberty in this workspace). Set LIB, NETLIST (a liberty-mapped synth),
# TOP=axi4_to_dfi_bridge in the env. Run: sta -exit syn/sta/opensta.tcl
if {![info exists ::env(LIB)] || ![info exists ::env(NETLIST)]} {
  puts "SKIP: set LIB + NETLIST (liberty-mapped). No liberty/OpenSTA in this workspace."; exit 0 }
read_liberty $::env(LIB)
read_verilog  $::env(NETLIST)
link_design   axi4_to_dfi_bridge
read_sdc      [file join [file dirname [info script]] .. constraints axi_dfi.sdc]
report_checks -path_delay max -digits 4
report_checks -path_delay min -digits 4
report_worst_slack -max ; report_worst_slack -min
report_tns ; report_wns
