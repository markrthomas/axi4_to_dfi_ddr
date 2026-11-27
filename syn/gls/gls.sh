#!/usr/bin/env bash
# gls.sh — canonical T6 gate-level simulation gate (OSS pathfinder, Yosys + Icarus).
#
# Part of the tapeout-readiness program (workspace DESIGN_READINESS.md). Adopt by
# copying into a repo's syn/gls/ and setting the vars below (or a repo syn/signoff.env).
#
# What this proves HERE (real artifact, no PDK needed):
#   - each top SYNTHESIZES to a generic gate netlist (Yosys), and
#   - that netlist SIMULATES CORRECTLY: the block's own self-checking directed
#     testbench passes when driven against the gate-level netlist (Yosys generic
#     cells modelled by the shipped simcells.v / simlib.v), not the RTL.
# This is zero-delay (functional) GLS — it catches synth/sim mismatch, lost
# initialization, and X-propagation that pure RTL sim and formal LEC can miss.
# It requires a Verilog/SV *directed, self-checking* TB (prints a PASSED line, calls
# $finish, prints no FAIL/ERROR/MISMATCH on success). A repo whose only self-checking
# TB is a cocotb/UVM/C++-Verilator harness cannot use this iverilog path as-is — author
# the Verilator-netlist recipe in T6_PLAN.md and tag the OSS run honestly, never a pass.
#
# External-netlist mode (post-route GLS, e.g. a LibreLane sky130 netlist — see
# templates/signoff/pnr/): set GLS_NETLIST_DIR and the same TBs run against
# <GLS_NETLIST_DIR>/<top>.nl.v with the given cell models instead of a Yosys netlist.
# Synthesis and chparam are skipped (the netlist is whatever P&R built, at the RTL
# defaults), and a missing tool is a FAIL, not a SKIP: that run was asked for explicitly.
#
# What this does NOT do: SDF back-annotated (timing) GLS — see T6_PLAN.md.
#
# Config (env or edit the defaults below):
#   TOPS        space-separated top module names
#   RTL         space-separated source files (hierarchy-complete)
#   FRONTEND    "verilog" (read_verilog -sv) | "slang" (read_slang; package-based SV)
#   RTL_INCDIR  include dir(s) for the yosys RTL read (default: none)
#   TB_INCDIR   include dir(s) for the iverilog TB compile (default: test)
#   TB_<top>    per-top self-checking TB(s), space-separated; ALL must pass (default:
#               <TB_INCDIR[0]>/tb_<top>.v). Add the block's protocol-compliance bench
#               here: on IP-axi-to-2apbs only the compliance bench caught a pre-fix AW/AR
#               deadlock at gate level; the directed TB passed. chparam overrides (step
#               0) are taken from the FIRST TB.
#   TB_EXTRA    extra non-synth Verilog the TB instantiates (checkers/BFMs) — compiled
#               WITH the TB + netlist, not synthesized (default: none)
#   OUT/BUILD   report / build dirs (default syn/gls/reports, syn/gls/build)
#   External-netlist mode (all optional; GLS_NETLIST_DIR switches it on):
#   GLS_NETLIST_DIR  dir holding <top>.nl.v (e.g. LibreLane runs/<tag>/final/nl)
#   GLS_NETLIST_PARAMS "NAME=VAL …" the netlist was built at (beyond the RTL defaults);
#                    a TB integer override that differs from the built value FAILs.
#   GLS_CELL_MODELS  cell model files (e.g. sky130_fd_sc_hd primitives.v + cell .v)
#   GLS_DEFINES      iverilog defines (e.g. "-DFUNCTIONAL -DUNIT_DELAY=#1")
#   GLS_LABEL        netlist description for the report
set -euo pipefail
# --- adopted defaults for axi4_to_dfi_ddr (override via env) ---
TOPS="${TOPS:-axi4_to_dfi_bridge}"
RTL="${RTL:-src/cdc_fifo_lib.v src/mc_dfi_scheduler.v src/axi4_bridge_frontend.v src/dfi_adapter.v src/axi4_to_dfi_bridge.v}"
FRONTEND="${FRONTEND:-verilog}"
RTL_INCDIR="${RTL_INCDIR:-src}"
TB_INCDIR="${TB_INCDIR:-src}"   # directed self-checking TB: src/tb_axi4_to_dfi_bridge.v
TB_EXTRA="${TB_EXTRA:-}"
EXT=0; [ -n "${GLS_NETLIST_DIR:-}" ] && EXT=1
OUT="${OUT:-syn/gls/reports}"; BUILD="${BUILD:-syn/gls/build$([ $EXT -eq 1 ] && echo -ext || true)}"
mkdir -p "$OUT" "$BUILD"
# Space-join: a newline-separated list (e.g. $(ls …)) is split by the yosys -p parser.
RTL="$(printf '%s ' $RTL)"

need() {  # SKIP in generic mode (OSS CAD Suite absent); FAIL in external-netlist mode
  command -v "$1" >/dev/null && return 0
  [ $EXT -eq 1 ] && { echo "[GLS] FAIL — $1 not on PATH"; exit 1; }
  echo "[GLS] $1 not on PATH — SKIP (needs OSS CAD Suite)"; exit 0
}
need iverilog; need vvp
if [ $EXT -eq 1 ]; then
  : "${GLS_CELL_MODELS:?GLS_CELL_MODELS must list the cell model files}"
  for f in $GLS_CELL_MODELS; do [ -f "$f" ] || { echo "[GLS] FAIL — cell model $f not found"; exit 1; }; done
  MODELS="$GLS_CELL_MODELS"; DEFS="${GLS_DEFINES:-}"; LABEL="${GLS_LABEL:-external netlist}"
else
  need yosys
  DAT="$(yosys-config --datdir 2>/dev/null || true)"
  [ -f "$DAT/simcells.v" ] && [ -f "$DAT/simlib.v" ] || { echo "[GLS] yosys simcells.v/simlib.v not found under '$DAT' — SKIP"; exit 0; }
  MODELS="$DAT/simcells.v $DAT/simlib.v"; DEFS=""; LABEL="generic Yosys gates (simcells/simlib models)"
fi

# Frontend / slang detection (integrated in Yosys>=0.67, else plugin, else SKIP honestly).
rinc=""; for d in $RTL_INCDIR; do rinc="$rinc -I$d"; done
if [ $EXT -eq 1 ]; then
  READ=""   # no synthesis in external-netlist mode
elif [ "$FRONTEND" = slang ]; then
  if yosys -q -p "read_slang" 2>&1 | grep -q "No such command"; then
    if yosys -q -p "plugin -i slang; read_slang" 2>&1 | grep -qE "No such command|Can't load module|cannot open"; then
      echo "[GLS] slang/sv-elab absent — SKIP (needs Yosys>=0.67 integrated, or the slang plugin)"; exit 0
    fi
    READ="plugin -i slang; read_slang $RTL"
  else
    READ="read_slang $RTL"
  fi
else
  READ="read_verilog -sv$rinc $RTL"
fi

tb_incs=""; for d in $TB_INCDIR; do tb_incs="$tb_incs -I$d"; done

rc=0
# TB integer parameter overrides for $TOP, one NAME=VALUE per line (shared by both modes).
tb_overrides() {  # $1 = TB file. NAME=VALUE per override; NAME=? if not an integer.
  # Literal overrides (.NAME(8), .NAME(4'd8)) are taken as-is; .NAME(IDENT) is resolved
  # through the TB's own `localparam|parameter [integer] IDENT = <int>`; anything else
  # (expressions, non-integer params) is reported as NAME=?.
  local nm vl
  awk -v top="$TOP" '
      $0 ~ "^[ \t]*"top"[ \t]*#\\(" {m=1}
      m {
        s=$0;
        if (match(s,/\)[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/)) s=substr(s,1,RSTART);  # stop at "<inst> ("
        while (match(s,/\.[A-Za-z_][A-Za-z0-9_]*[ \t]*\([^()]*\)/)) {
          t=substr(s,RSTART,RLENGTH); sub(/^\./,"",t);
          sub(/[ \t]*\([ \t]*/,"=",t); sub(/[ \t]*\)$/,"",t);
          print t; s=substr(s,RSTART+RLENGTH)
        }
      }
      m && /\)[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/ {exit}
  ' "$1" | while IFS='=' read -r nm vl; do
    [ -n "$nm" ] || continue
    if [[ "$vl" =~ ^[0-9][0-9_]*(\'[bdhBDH][0-9a-fA-F_]+)?$ ]]; then echo "$nm=$vl"
    elif [[ "$vl" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      r="$(grep -oE "(localparam|parameter)[[:space:]]+(integer[[:space:]]+)?$vl[[:space:]]*=[[:space:]]*[0-9][0-9_]*[[:space:]]*[;,)]" "$1" | head -1 | sed -E 's/.*=[[:space:]]*([0-9_]+).*/\1/')"
      echo "$nm=${r:-?}"
    else echo "$nm=?"
    fi
  done
}
for TOP in $TOPS; do
  echo "[GLS] === $TOP ($LABEL) ==="
  tbv="TB_${TOP//[^A-Za-z0-9_]/_}"; firstinc="${TB_INCDIR%% *}"
  tbs="${!tbv:-$firstinc/tb_$TOP.v}"; tb="${tbs%% *}"
  missing=0; for t in $tbs; do [ -f "$t" ] || { echo "[GLS] $TOP: no self-checking TB ($t) — FAIL (set TB_$TOP)"; missing=1; }; done
  [ $missing -eq 0 ] || { rc=1; continue; }

  net="$BUILD/$TOP.gls.v"; netp="$BUILD/$TOP.gls.param.v"; rpt="$OUT/$TOP.gls.rpt"
  if [ $EXT -eq 1 ]; then
    net="$GLS_NETLIST_DIR/$TOP.nl.v"
    [ -f "$net" ] || { echo "[GLS] $TOP: FAIL — netlist $net not found"; rc=1; continue; }
  else

  # 0) a directed TB may instantiate the DUT with BEHAVIOURAL parameter overrides (not
  #    just widths). `synth` constant-folds params to the value present AT SYNTH TIME, so
  #    the netlist must be built at the TB's values or the override silently has no effect
  #    (the gate is frozen at the RTL default). Extract the TB's `.NAME(intliteral)`
  #    overrides for this DUT and apply them with `chparam -set` before synth. A
  #    non-integer override (an expression / param) is skipped — if it changes behaviour
  #    the GLS will then FAIL honestly rather than pass on a wrongly-folded netlist.
  #    `GLS_CHPARAM_<top>="NAME=VAL …"` (env) supplements / overrides the auto-extraction.
  chp=""
  while IFS='=' read -r nm vl; do
    [ -n "$nm" ] && [ "$vl" != "?" ] && chp="$chp chparam -set $nm $vl $TOP;"
  done < <(tb_overrides "$tb")
  gcv="GLS_CHPARAM_${TOP//[^A-Za-z0-9_]/_}"
  for kv in ${!gcv:-}; do nm="${kv%%=*}"; vl="${kv#*=}"; [ -n "$nm" ] && chp="$chp chparam -set $nm $vl $TOP;"; done

  # 1) synthesize to a generic gate netlist (same mapping as the T1 gate), at the TB's
  #    parameter values (chparam) so behavioural overrides are honoured.
  if ! yosys -q -l "$BUILD/$TOP.synth.log" -p "
      $READ
      $chp
      hierarchy -check -top $TOP
      proc
      synth -top $TOP -flatten
      write_verilog -noattr $net
  "; then
    echo "[GLS] $TOP: FAIL — synthesis error (see $BUILD/$TOP.synth.log)"; rc=1; continue
  fi
  [ -n "$chp" ] && echo "[GLS] $TOP: synthesized at TB param overrides:$(echo "$chp" | sed -E 's/chparam -set //g; s/ '"$TOP"';/ /g')"
  fi   # end generic-netlist synthesis (steps 0-1)

  # 2) synth constant-folds the top's parameters away; a directed TB may instantiate
  #    the DUT with named param overrides (at the RTL defaults). Re-insert the RTL
  #    top's ANSI parameter defaults as a no-op shim so that override stays legal. The
  #    defaults are read from the RTL header (not hard-coded) so this self-maintains.
  #    Find the RTL file that declares the top, lift each `parameter ...` declaration,
  #    and inject it as its OWN statement — preserving the optional type keyword
  #    (`parameter integer X = 32`) and normalized spacing, and keeping source order so
  #    dependent defaults (e.g. `MASK = DATA/8`) still resolve. One joined statement or
  #    collapsed whitespace would break both. `localparam`s are not overridable — skip.
  topsrc=""; for f in $RTL; do grep -qE "^[ \t]*module[ \t]+$TOP\b" "$f" 2>/dev/null && { topsrc="$f"; break; }; done
  decls="$BUILD/$TOP.params.txt"; : > "$decls"
  [ -n "$topsrc" ] && awk -v top="$TOP" '
      $0 ~ "^[ \t]*module[ \t]+"top"[ \t]*[#(]" {m=1}
      m && /parameter/ && !/localparam/ {
          s=$0; sub(/.*parameter[ \t]+/,"",s); sub(/\/\/.*/,"",s);
          gsub(/\r/,"",s); sub(/,[ \t]*$/,"",s);
          gsub(/[ \t]+/," ",s); sub(/^ /,"",s); sub(/ $/,"",s);
          if (s!="") print s
      }
      m && /^[ \t]*\)/ {exit}
  ' "$topsrc" > "$decls"
  if [ -s "$decls" ]; then
    awk -v top="$TOP" -v df="$decls" 'BEGIN{d=0}
      $0 ~ "^[ \t]*module[ \t]+"top"[ \t]*\\(" {m=1}
      {print}
      m && !d && /\);[ \t\r]*$/ { while((getline p < df) > 0) print "  parameter " p ";"; d=1; m=0 }
    ' "$net" > "$netp"
  else
    cp "$net" "$netp"
  fi

  # 2b) external netlist: its parameters were fixed when it was built (RTL defaults plus
  #     GLS_NETLIST_PARAMS="NAME=VAL …", e.g. LibreLane SYNTH_PARAMETERS). The shim above
  #     makes a TB override legal but INERT, so a TB override that differs from the built
  #     value would silently test different hardware: FAIL instead. Values are compared as
  #     plain integer literals (sized literals / expressions are compared as text).
  if [ $EXT -eq 1 ]; then
    pm=0
    for t in $tbs; do
      while IFS='=' read -r nm vl; do
        [ -n "$nm" ] || continue
        if [ "$vl" = "?" ]; then
          echo "[GLS] $TOP: WARNING — $(basename "$t") override of $nm is not an integer/resolvable; NOT checked against the netlist"
          continue
        fi
        built=""
        for kv in ${GLS_NETLIST_PARAMS:-}; do [ "${kv%%=*}" = "$nm" ] && built="${kv#*=}"; done
        [ -n "$built" ] || built="$(awk -v n="$nm" '$0 ~ "(^|[ \t])"n"[ \t]*=" { s=$0; sub(/^[^=]*=[ \t]*/,"",s); print s; exit }' "$decls")"
        [ "${built//_/}" = "${vl//_/}" ] && continue
        echo "[GLS] $TOP: FAIL — $(basename "$t") overrides $nm=$vl but the netlist was built at $nm=${built:-<unknown>}" \
             "(rebuild it at the TB value, e.g. LibreLane SYNTH_PARAMETERS + GLS_NETLIST_PARAMS)"
        pm=1
      done < <(tb_overrides "$t")
    done
    [ $pm -eq 0 ] || { rc=1; continue; }
  fi

  # 3) compile + run each self-checking TB (+ any non-synth checkers/BFMs it
  #    instantiates) against the netlist + cell models. PASS requires, per TB: the sim
  #    reaches an explicit $finish (Icarus prints "$finish called at …"), prints a
  #    PASSED line, and prints no FAIL/ERROR/MISMATCH.
  results=""; top_ok=1
  for t in $tbs; do
    nm="$(basename "$t" .v)"; bin="$BUILD/sim_gls_${TOP}_$nm"; runlog="$OUT/$TOP.$nm.gls.log"
    if ! iverilog -g2012 $DEFS $tb_incs -o "$bin" "$t" $TB_EXTRA "$netp" $MODELS 2> "$BUILD/$TOP.$nm.iverilog.log"; then
      echo "[GLS] $TOP/$nm: FAIL — gate-level compile error (see $BUILD/$TOP.$nm.iverilog.log):"
      grep -iE 'error' "$BUILD/$TOP.$nm.iverilog.log" | head; top_ok=0
      results="$results\n  testbench ......... $t: FAIL (compile)"; continue
    fi
    # Pass = vvp exit 0 (a $fatal exits 1) + a PASS marker + no failure marker
    # (substring, any case) on any line that is not itself a PASS line, so a passing
    # test NAMED e.g. "PASS smoke error_injection" is not read as an error. No
    # "$finish called" requirement: vvp prints it for $finish(1|2) but not $finish(0).
    # These TBs run free clocks, so the sim only ends via $finish/$fatal; a hang is
    # caught by the timeout below (FAIL), not by a log string.
    vrc=0; timeout "${GLS_TIMEOUT:-3600}" vvp -n "$bin" > "$runlog" 2>&1 || vrc=$?
    [ $vrc -eq 124 ] && echo "[GLS] $TOP/$nm: TIMEOUT after ${GLS_TIMEOUT:-3600}s (hang?)" >> "$runlog"
    if [ $vrc -eq 0 ] \
       && grep -qiE '\bPASS(ED)?\b' "$runlog" \
       && ! grep -viE '^[[:space:]]*PASS(ED)?\b' "$runlog" | grep -qiE 'FAIL|ERROR|MISMATCH|FATAL|TIMEOUT'; then
      echo "[GLS] $TOP/$nm: PASS"
      results="$results\n  testbench ......... $t: PASS ($(grep -iE '\bPASS(ED)?\b' "$runlog" | head -1 | sed 's/^[[:space:]]*//'))"
    else
      echo "[GLS] $TOP/$nm: FAIL — gate-level sim did not pass (see $runlog):"
      tail -15 "$runlog"; top_ok=0
      results="$results\n  testbench ......... $t: FAIL (see $(basename "$runlog"))"
    fi
  done
  {
    echo "# $TOP — gate-level simulation report (T6, functional GLS)"
    echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "  netlist ........... $LABEL$([ $EXT -eq 1 ] && echo " ($net)")"
    [ -n "$DEFS" ] && echo "  defines ........... $DEFS"
    printf '%b\n' "${results#\\n}"
    echo "  result ............ $([ $top_ok -eq 1 ] && echo PASS || echo FAIL)"
  } > "$rpt"
  [ $top_ok -eq 1 ] && echo "[GLS] $TOP: PASS (report: $rpt)" || rc=1
done
[ $rc -eq 0 ] && echo "[GLS] T6 gate-level simulation PASSED ($LABEL; SDF-timing GLS = separate step)."
exit $rc
