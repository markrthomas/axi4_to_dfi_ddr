#!/usr/bin/env bash
# scan_readiness.sh — T4 DFT scan-readiness audit for axi4_to_dfi_bridge (OSS, Yosys).
#
# Tapeout-readiness program T4 (../../../DESIGN_READINESS.md). Adopted from the sign-off
# kit's canonical scan_readiness.sh. Real scan insertion + ATPG need commercial tools
# (DFT Compiler / TestMAX / Tessent) + a PDK (needs-license — see DFT_PLAN.md). What runs
# HERE, no PDK, is the structural scan-readiness audit on the synthesized netlist: the
# conditions that must hold BEFORE scan insertion.
#
# HARD gates (fail => NOT scan-ready):
#   - latch-free (a D-latch is not scannable); no combinational loops (ATPG can't justify).
# REPORTED (scan-planning inputs): flop count (scan length), reset controllability,
#   async set/reset count, memory/RAM (MBIST) count.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; cd "$ROOT"

TOPS="${TOPS:-axi4_to_dfi_bridge}"
# Core synthesizable RTL, dependency order (same set as `make synth` BRIDGE_SRCS).
RTL="${RTL:-src/cdc_fifo_lib.v src/mc_dfi_scheduler.v src/axi4_bridge_frontend.v src/dfi_adapter.v src/axi4_to_dfi_bridge.v}"
INCDIRS="${INCDIRS:-src}"
OUT="${OUT:-syn/dft/reports}"; mkdir -p "$OUT"
command -v yosys >/dev/null || { echo "[DFT] yosys not on PATH; SKIP"; exit 0; }
# Space-join: a newline-separated list (e.g. $(ls …)) is split by the yosys -p parser.
RTL="$(printf '%s ' $RTL)"
INC=""; for d in $INCDIRS; do INC="$INC -I $d"; done

rc=0
for TOP in $TOPS; do
  echo "[DFT] === $TOP ==="
  log="$OUT/$TOP.dft.log"; stat="$OUT/$TOP.stat.txt"; rpt="$OUT/$TOP.scan.rpt"
  if ! yosys -q -l "$log" -p "
      read_verilog -sv$INC $RTL
      hierarchy -check -top $TOP
      proc; opt -full
      synth -top $TOP -flatten
      select -assert-none t:\$dlatch t:\$_DLATCH_*
      check -assert
      tee -o $stat stat
  "; then
    echo "[DFT] $TOP: FAIL — latch inferred or combinational loop (see $log)"; rc=1; continue
  fi
  read -r tot nores async lat mem < <(awk '
    $2 ~ /^\$_DLATCH/ {lat+=$1}
    $2 ~ /^\$_S?DFF/   {tot+=$1;
        if ($2 ~ /^\$_DFF_[NP]_$/ || $2 ~ /^\$_DFFE_[NP][NP]_$/) nores+=$1;
        if ($2 ~ /^\$_DFFSR/ || $2 ~ /^\$_DFF_[NP][NP][01]_$/ || $2 ~ /^\$_DFFE_[NP][NP][01][NP]_$/) async+=$1 }
    $2 ~ /^\$mem/      {mem+=$1}
    END{printf "%d %d %d %d %d\n", tot+0, nores+0, async+0, lat+0, mem+0}' "$stat") || true
  res=$(( tot - nores )); pct=0; [ "$tot" -gt 0 ] && pct=$(( res * 100 / tot ))
  {
    echo "# $TOP — scan-readiness report (T4, OSS structural audit)"
    echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "HARD GATES"
    echo "  latch-free ................. PASS (0 D-latches)"
    echo "  no combinational loops ..... PASS (yosys check -assert)"
    echo
    echo "SCAN-PLANNING INVENTORY"
    echo "  flip-flops (scan length) ... $tot"
    echo "    reset-controllable ....... $res (${pct}%)"
    echo "    no set/reset ............. $nores"
    echo "    async set/reset .......... $async"
    echo "  latches (must be 0) ........ $lat"
    echo "  memory arrays (MBIST) ...... $mem"
  } > "$rpt"
  echo "[DFT] $TOP: scan-ready — flops=$tot reset-controllable=${pct}% async_sr=$async mem=$mem (report: $rpt)"
done
[ $rc -eq 0 ] && echo "[DFT] T4 scan-readiness audit PASSED (OSS; scan insertion + ATPG = needs-license)."
exit $rc
