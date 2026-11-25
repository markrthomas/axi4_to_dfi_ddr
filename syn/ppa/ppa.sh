#!/usr/bin/env bash
# ppa.sh — canonical T6 PPA (power/performance/area) proxy baseline (OSS, Yosys).
#
# Part of the tapeout-readiness program (workspace DESIGN_READINESS.md). Adopt by
# copying into a repo's syn/ppa/ and setting the vars below. Real PPA needs a PDK: a
# standard-cell library (area/power per cell), Liberty timing, and a place&route flow —
# those are needs-pdk (see PPA_PLAN.md for the authored OpenROAD/sky130 + OpenSTA
# recipe). What runs HERE, no PDK, is a technology-independent PROXY baseline that is a
# real, tracked artifact and moves monotonically with the real numbers:
#   - AREA proxy  = generic cell count + flop count (post-synth, flattened).
#   - TIMING proxy= longest topological logic path (`ltp`), i.e. combinational depth.
#   - POWER proxy = flop count (switching surface) — informational.
# These are the same ceilings the T1 gate calibrates; this consolidates them into a
# per-top PPA table for tracking across revisions.
#
# Config (env or edit the defaults below):
#   TOPS        space-separated top module names
#   RTL         space-separated source files (hierarchy-complete)
#   FRONTEND    "verilog" (read_verilog -sv) | "slang" (read_slang; package-based SV)
#   RTL_INCDIR  include dir(s) for the yosys RTL read (default: none)
#   OUT         report dir (default syn/ppa/reports)
set -euo pipefail
# --- adopted defaults for axi4_to_dfi_ddr (override via env) ---
TOPS="${TOPS:-axi4_to_dfi_bridge}"
RTL="${RTL:-src/cdc_fifo_lib.v src/mc_dfi_scheduler.v src/axi4_bridge_frontend.v src/dfi_adapter.v src/axi4_to_dfi_bridge.v}"
FRONTEND="${FRONTEND:-verilog}"; RTL_INCDIR="${RTL_INCDIR:-src}"
OUT="${OUT:-syn/ppa/reports}"; mkdir -p "$OUT"
RTL="$(printf '%s ' $RTL)"
command -v yosys >/dev/null || { echo "[PPA] yosys not on PATH — SKIP"; exit 0; }

rinc=""; for d in $RTL_INCDIR; do rinc="$rinc -I$d"; done
if [ "$FRONTEND" = slang ]; then
  if yosys -q -p "read_slang" 2>&1 | grep -q "No such command"; then
    if yosys -q -p "plugin -i slang; read_slang" 2>&1 | grep -qE "No such command|Can't load module|cannot open"; then
      echo "[PPA] slang/sv-elab absent — SKIP (needs Yosys>=0.67 integrated, or the slang plugin)"; exit 0
    fi
    READ="plugin -i slang; read_slang $RTL"
  else
    READ="read_slang $RTL"
  fi
else
  READ="read_verilog -sv$rinc $RTL"
fi

rc=0
for TOP in $TOPS; do
  echo "[PPA] === $TOP ==="
  log="$OUT/$TOP.ppa.log"; rpt="$OUT/$TOP.ppa.rpt"
  if ! yosys -q -l "$log" -p "
      $READ
      hierarchy -check -top $TOP
      proc
      synth -top $TOP -flatten
      tee -o $OUT/$TOP.ppa.stat.txt stat
      tee -o $OUT/$TOP.ppa.ltp.txt ltp
  "; then
    echo "[PPA] $TOP: FAIL — synthesis error (see $log)"; rc=1; continue
  fi
  cells=$( (grep -oE '[0-9]+ +cells' "$OUT/$TOP.ppa.stat.txt" || true) | tail -1 | grep -oE '[0-9]+' || echo "?")
  flops=$( (grep -oE '[0-9]+ +\$_(S?DFF|DLATCH)[A-Z0-9_]*' "$OUT/$TOP.ppa.stat.txt" || true) | awk '{s+=$1} END{print s+0}')
  depth=$( (grep -oiE 'length=[0-9]+' "$OUT/$TOP.ppa.ltp.txt" || true) | tail -1 | grep -oE '[0-9]+' || echo "?")
  {
    echo "# $TOP — PPA proxy baseline (T6, OSS technology-independent)"
    echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "  AREA proxy   — generic cells ........ ${cells}"
    echo "  AREA proxy   — flip-flops ........... ${flops}"
    echo "  TIMING proxy — logic depth (ltp) .... ${depth}"
    echo "  real PPA (ns / mW / um^2) ........... needs-pdk (see PPA_PLAN.md)"
  } > "$rpt"
  echo "[PPA] $TOP: cells=${cells} flops=${flops} logic-depth=${depth} (report: $rpt)"
done
[ $rc -eq 0 ] && echo "[PPA] T6 PPA proxy baseline emitted (OSS; real node PPA = needs-pdk)."
exit $rc
