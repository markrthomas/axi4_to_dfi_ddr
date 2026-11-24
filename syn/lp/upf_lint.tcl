#!/usr/bin/env tclsh
# upf_lint.tcl — tool-free IEEE-1801 (UPF) consistency lint.
#
# Tapeout-readiness program T3 (../../DESIGN_READINESS.md). No OSS tool models UPF power
# *semantics* (that is the VCS `-upf` run, needs-license — see LP_PLAN.md). What this does,
# with no tool, is catch a *malformed or inconsistent* UPF before it reaches the licensed
# flow: it stubs the UPF commands, sources the file, and cross-checks that every supply,
# domain, isolation/retention strategy and power-state table resolves to something defined.
#
# Usage: tclsh upf_lint.tcl <file.upf>   (exit 0 = consistent, 1 = errors, 2 = usage)
set ::errs 0
proc err {m} { puts "  ERROR: $m"; incr ::errs }

array set ::dom {} ; array set ::snet {} ; array set ::dsupply {}
array set ::iso {} ; array set ::isoctl {} ; array set ::ret {} ; array set ::retctl {}
array set ::pst {} ; set ::pststates {} ; set ::top ""

proc opts {argl} {                    ;# -flag value pairs from an arg list
  set d [dict create]
  for {set i 0} {$i < [llength $argl]} {incr i} {
    set a [lindex $argl $i]
    if {[string match -* $a]} { dict set d $a [lindex $argl [expr {$i+1}]]; incr i }
  }
  return $d
}
proc name1 {argl} { return [lindex $argl 0] }      ;# first positional (the entity name)
proc chkdom {d what} {
  if {[dict exists $d -domain]} { set dm [dict get $d -domain]
    if {![info exists ::dom($dm)]} { err "$what references undefined domain $dm" } }
}

# --- stubbed UPF commands (record + check) ---
proc set_design_top {args} { set ::top [name1 $args] }
proc create_power_domain {args} { set ::dom([name1 $args]) 1 }
proc create_supply_port {args} { set ::snet([name1 $args]) 1; chkdom [opts $args] "supply_port [name1 $args]" }
proc create_supply_net  {args} { set ::snet([name1 $args]) 1; chkdom [opts $args] "supply_net [name1 $args]" }
proc set_domain_supply_net {args} {
  set dm [name1 $args]; set d [opts $args]
  if {![info exists ::dom($dm)]} { err "set_domain_supply_net: undefined domain $dm" }
  foreach f {-primary_power_net -primary_ground_net} {
    if {![dict exists $d $f]} { err "set_domain_supply_net $dm: missing $f" } \
    elseif {![info exists ::snet([dict get $d $f])]} { err "set_domain_supply_net $dm: $f [dict get $d $f] not created" }
  }
  set ::dsupply($dm) 1
}
proc create_power_switch {args} {
  set nm [name1 $args]; set d [opts $args]
  if {![dict exists $d -domain] || ![info exists ::dom([dict get $d -domain])]} { err "power_switch $nm: bad/undefined -domain" }
  foreach f {-input_supply_port -output_supply_port -control_port} { if {![dict exists $d $f]} { err "power_switch $nm: missing $f" } }
  foreach f {-input_supply_port -output_supply_port} {
    if {[dict exists $d $f]} { set net [lindex [dict get $d $f] 1]
      if {$net ne "" && ![info exists ::snet($net)]} { err "power_switch $nm: $f net $net not created" } }
  }
  if {![dict exists $d -on_state] && ![dict exists $d -off_state]} { err "power_switch $nm: no on/off state" }
}
proc set_isolation {args} { set nm [name1 $args]; set d [opts $args]
  set dm [expr {[dict exists $d -domain]?[dict get $d -domain]:""}]
  if {![info exists ::dom($dm)]} { err "isolation $nm: undefined -domain $dm" }; set ::iso($nm) $dm }
proc set_isolation_control {args} { set ::isoctl([name1 $args]) 1 }
proc set_retention {args} { set nm [name1 $args]; set d [opts $args]
  set dm [expr {[dict exists $d -domain]?[dict get $d -domain]:""}]
  if {![info exists ::dom($dm)]} { err "retention $nm: undefined -domain $dm" }; set ::ret($nm) $dm }
proc set_retention_control {args} { set ::retctl([name1 $args]) 1 }
proc create_pst {args} { set nm [name1 $args]; set d [opts $args]
  set sup [expr {[dict exists $d -supplies]?[dict get $d -supplies]:{}}]; set ::pst($nm) $sup
  foreach n $sup { if {![info exists ::snet($n)]} { err "pst $nm: supply $n not created" } } }
proc add_pst_state {args} { set nm [name1 $args]; set d [opts $args]
  set p [expr {[dict exists $d -pst]?[dict get $d -pst]:""}]
  if {![info exists ::pst($p)]} { err "pst_state $nm: undefined -pst $p" } \
  elseif {[dict exists $d -state]} { set ns [llength [dict get $d -state]]; set nsup [llength $::pst($p)]
    if {$ns != $nsup} { err "pst_state $nm: $ns states != $nsup supplies in $p" } }
  lappend ::pststates $nm }
proc unknown {args} { return }        ;# swallow any other UPF command

# --- run ---
if {$argc < 1} { puts "usage: upf_lint.tcl <file.upf>"; exit 2 }
set f [lindex $argv 0]
puts "\[LP\] UPF consistency lint: $f"
source $f

if {$::top eq ""} { err "no set_design_top" }
foreach {s dm} [array get ::iso] { if {![info exists ::isoctl($s)]} { err "isolation $s has no set_isolation_control" } }
foreach {s dm} [array get ::ret] { if {![info exists ::retctl($s)]} { err "retention $s has no set_retention_control" } }
foreach dm [array names ::dom] { if {![info exists ::dsupply($dm)]} { err "domain $dm has no set_domain_supply_net" } }
if {[array size ::pst] == 0} { err "no create_pst" }
if {[llength $::pststates] == 0} { err "no add_pst_state" }

puts "\[LP\] domains=[array size ::dom] supplies=[array size ::snet] iso=[array size ::iso] ret=[array size ::ret] pst_states=[llength $::pststates]"
if {$::errs > 0} { puts "\[LP\] FAIL: $::errs UPF consistency error(s)."; exit 1 }
puts "\[LP\] PASS: UPF internally consistent (power semantics unchecked — needs VCS -upf, see LP_PLAN.md)."
exit 0
