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
# What this does NOT do (needs a PDK / liberty + a vendor flow — see T6_PLAN.md):
#   - SDF back-annotated (timing) GLS, or mapping to a real standard-cell library.
#
# Config (env or edit the defaults below):
#   TOPS        space-separated top module names
#   RTL         space-separated source files (hierarchy-complete)
#   FRONTEND    "verilog" (read_verilog -sv) | "slang" (read_slang; package-based SV)
#   RTL_INCDIR  include dir(s) for the yosys RTL read (default: none)
#   TB_INCDIR   include dir(s) for the iverilog TB compile (default: test)
#   TB_<top>    per-top self-checking directed TB (default: <TB_INCDIR[0]>/tb_<top>.v)
#   TB_EXTRA    extra non-synth Verilog the TB instantiates (checkers/BFMs) — compiled
#               WITH the TB + netlist, not synthesized (default: none)
#   OUT/BUILD   report / build dirs (default syn/gls/reports, syn/gls/build)
set -euo pipefail
# --- adopted defaults for axi4_to_dfi_ddr (override via env) ---
TOPS="${TOPS:-axi4_to_dfi_bridge}"
RTL="${RTL:-src/cdc_fifo_lib.v src/mc_dfi_scheduler.v src/axi4_bridge_frontend.v src/dfi_adapter.v src/axi4_to_dfi_bridge.v}"
FRONTEND="${FRONTEND:-verilog}"
RTL_INCDIR="${RTL_INCDIR:-src}"
TB_INCDIR="${TB_INCDIR:-src}"   # directed self-checking TB: src/tb_axi4_to_dfi_bridge.v
TB_EXTRA="${TB_EXTRA:-}"
OUT="${OUT:-syn/gls/reports}"; BUILD="${BUILD:-syn/gls/build}"
mkdir -p "$OUT" "$BUILD"
# Space-join: a newline-separated list (e.g. $(ls …)) is split by the yosys -p parser.
RTL="$(printf '%s ' $RTL)"

command -v yosys   >/dev/null || { echo "[GLS] yosys not on PATH — SKIP (needs OSS CAD Suite)";   exit 0; }
command -v iverilog>/dev/null || { echo "[GLS] iverilog not on PATH — SKIP (needs OSS CAD Suite)"; exit 0; }
command -v vvp     >/dev/null || { echo "[GLS] vvp not on PATH — SKIP (needs OSS CAD Suite)";      exit 0; }
DAT="$(yosys-config --datdir 2>/dev/null || true)"
[ -f "$DAT/simcells.v" ] && [ -f "$DAT/simlib.v" ] || { echo "[GLS] yosys simcells.v/simlib.v not found under '$DAT' — SKIP"; exit 0; }

# Frontend / slang detection (integrated in Yosys>=0.67, else plugin, else SKIP honestly).
rinc=""; for d in $RTL_INCDIR; do rinc="$rinc -I$d"; done
if [ "$FRONTEND" = slang ]; then
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
for TOP in $TOPS; do
  echo "[GLS] === $TOP ==="
  tbv="TB_${TOP//[^A-Za-z0-9_]/_}"; firstinc="${TB_INCDIR%% *}"
  tb="${!tbv:-$firstinc/tb_$TOP.v}"
  [ -f "$tb" ] || { echo "[GLS] $TOP: no self-checking directed TB ($tb) — FAIL (set TB_$TOP)"; rc=1; continue; }

  net="$BUILD/$TOP.gls.v"; netp="$BUILD/$TOP.gls.param.v"; bin="$BUILD/sim_gls_$TOP"
  runlog="$OUT/$TOP.gls.log"; rpt="$OUT/$TOP.gls.rpt"

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
    [ -n "$nm" ] && chp="$chp chparam -set $nm $vl $TOP;"
  done < <(awk -v top="$TOP" '
      $0 ~ "^[ \t]*"top"[ \t]*#\\(" {m=1}
      m {
        s=$0;
        while (match(s,/\.[A-Za-z_][A-Za-z0-9_]*[ \t]*\([ \t]*[0-9][0-9_]*('"'"'[bdhBDH][0-9a-fA-F_]+)?[ \t]*\)/)) {
          t=substr(s,RSTART,RLENGTH); sub(/^\./,"",t);
          sub(/[ \t]*\([ \t]*/,"=",t); gsub(/[ \t)]/,"",t);
          print t; s=substr(s,RSTART+RLENGTH)
        }
      }
      m && /\)[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/ {exit}
  ' "$tb")
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
      $0 ~ "^module "top"\\(" {m=1}
      {print}
      m && !d && /\);[ \t]*$/ { while((getline p < df) > 0) print "  parameter " p ";"; d=1; m=0 }
    ' "$net" > "$netp"
  else
    cp "$net" "$netp"
  fi

  # 3) compile the self-checking TB (+ any non-synth checkers/BFMs it instantiates)
  #    against the gate netlist + Yosys sim models.
  if ! iverilog -g2012 $tb_incs -o "$bin" "$tb" $TB_EXTRA "$netp" "$DAT/simcells.v" "$DAT/simlib.v" 2> "$BUILD/$TOP.iverilog.log"; then
    echo "[GLS] $TOP: FAIL — gate-level compile error (see $BUILD/$TOP.iverilog.log):"
    grep -iE 'error:' "$BUILD/$TOP.iverilog.log" | head; rc=1; continue
  fi

  # 4) run; the TB is self-checking. PASS requires: the sim reaches an explicit $finish
  #    (Icarus prints "$finish called at …"), prints a PASSED line, and prints no
  #    FAIL/ERROR/MISMATCH.
  vvp "$bin" > "$runlog" 2>&1 || true
  # PASS token is a whole word (\b…\b excludes BYPASS etc.); matches PASS, PASS:, PASSED.
  # Exclusion is substring FAIL/ERROR/MISMATCH (SLVERR ≠ ERROR, so AXI err names are safe).
  if grep -qiE '\bPASS(ED)?\b' "$runlog" \
     && ! grep -qiE 'FAIL|ERROR|MISMATCH' "$runlog" \
     && grep -qE '\$finish' "$runlog"; then
    {
      echo "# $TOP — gate-level simulation report (T6, OSS zero-delay GLS)"
      echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "  netlist ........... generic Yosys gates (simcells/simlib models)"
      echo "  testbench ......... $tb (self-checking directed)"
      echo "  result ............ PASS ($(grep -iE '\bPASS(ED)?\b' "$runlog" | head -1 | sed 's/^[[:space:]]*//'))"
    } > "$rpt"
    echo "[GLS] $TOP: PASS — gate-level netlist simulates clean (report: $rpt)"
  else
    echo "[GLS] $TOP: FAIL — gate-level sim did not pass (see $runlog):"
    tail -15 "$runlog"; rc=1
  fi
done
[ $rc -eq 0 ] && echo "[GLS] T6 gate-level simulation PASSED (OSS zero-delay; SDF-timing GLS + real PPA = needs-pdk)."
exit $rc
