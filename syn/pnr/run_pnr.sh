#!/usr/bin/env bash
# run_pnr.sh — open-PDK RTL-to-GDS for one top with LibreLane (T2/T6 silicon run).
# Kit template (templates/signoff/pnr/); adopt into syn/pnr/.
#
#   syn/pnr/run_pnr.sh <top>          # needs syn/pnr/<top>/config.json
#
# Runs LibreLane's Classic flow (synthesis, floorplan, PDN, placement, CTS, routing,
# parasitic extraction, multi-corner STA, DRC, LVS) on sky130A / sky130_fd_sc_hd using
# syn/pnr/<top>/config.json and the repo's T2 SDC. The run goes
# to syn/pnr/<top>/runs/<tag>/ (gitignored); syn/pnr/summarize.py then writes
# syn/pnr/reports/<top>.pnr.rpt (gitignored; CI artifact, and archived in the release
# bundle when present).
#
# Needs: Python 3.10+, `pip install librelane`, Docker. The sky130 PDK is fetched by
# LibreLane through ciel into $PDK_ROOT (default ~/.ciel). Heavy: run in CI
# (.github/workflows/silicon.yml), not on a small workstation.
set -euo pipefail
TOP="${1:?usage: run_pnr.sh <top>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CFG="$ROOT/syn/pnr/$TOP/config.json"
TAG="${PNR_RUN_TAG:-ci}"
PDK_ROOT="${PDK_ROOT:-$HOME/.ciel}"
[ -f "$CFG" ] || { echo "[PNR] FAIL: no config $CFG"; exit 2; }

cd "$ROOT"
echo "[PNR] $TOP: librelane $(python3 -m pip show librelane 2>/dev/null | sed -n 's/^Version: //p'), PDK root $PDK_ROOT"
CMD=(python3 -m librelane --dockerized --pdk-root "$PDK_ROOT" --run-tag "$TAG" --overwrite "$CFG")
rc=0
if [ -t 0 ]; then
  "${CMD[@]}" || rc=$?
else
  # --dockerized starts the container with a TTY; CI has no terminal, so give it a
  # pseudo-terminal with script(1). Its exit status is the command's (-e).
  script -qefc "$(printf '%q ' "${CMD[@]}")" /dev/null </dev/null || rc=$?
fi
RUN="$ROOT/syn/pnr/$TOP/runs/$TAG"
echo "[PNR] $TOP: LibreLane exit code $rc (run dir $RUN)"
python3 "$ROOT/syn/pnr/summarize.py" "$TOP" "$RUN" "$rc"
