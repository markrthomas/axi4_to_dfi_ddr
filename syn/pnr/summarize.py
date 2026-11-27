#!/usr/bin/env python3
"""Summarise a LibreLane sky130 run into syn/pnr/reports/<top>.pnr.rpt.

    syn/pnr/summarize.py <top> <run-dir> <librelane-exit-code>

Reads <run-dir>/final/metrics.json (written by LibreLane) and reports area, power,
timing per corner (setup/hold WNS + TNS, Fmax), DRC, LVS, antenna and electrical
rule counts.

Gate (exit code):
  FAIL (1) if the flow did not complete or produced no GDS, if any DRC / LVS error
  is reported, or if hold is violated at any corner.
  Setup is checked against the config's CLOCK_PERIOD. By default a miss is reported
  as "SETUP NOT MET" plus the achievable Fmax per corner, with a GitHub warning
  annotation, but does not fail the run (for a placeholder clock target). Set
  PNR_SETUP_GATE=1 to make a setup miss FAIL once the clock budget is real.
A metric that LibreLane did not report is printed as "not reported", never as a pass.
"""
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path.cwd()   # run from the repo root (run_pnr.sh does)


def fmt(v, unit="", nd=3):
    if v is None:
        return "not reported"
    if isinstance(v, float):
        return f"{v:.{nd}f}{unit}"
    return f"{v}{unit}"


def main() -> int:
    top, run, rc = sys.argv[1], Path(sys.argv[2]), int(sys.argv[3])
    out_dir = ROOT / "syn/pnr/reports"
    out_dir.mkdir(parents=True, exist_ok=True)
    rpt = out_dir / f"{top}.pnr.rpt"
    lines, fails, warns = [], [], []
    say = lines.append

    mfile = run / "final" / "metrics.json"
    m = json.loads(mfile.read_text()) if mfile.is_file() else {}
    gds = sorted((run / "final").glob("gds/*.gds")) if (run / "final").is_dir() else []
    period = json.loads((ROOT / f"syn/pnr/{top}/config.json").read_text()).get("CLOCK_PERIOD")

    cfg = json.loads((ROOT / f"syn/pnr/{top}/config.json").read_text())
    # Clocks declared in the sign-off SDC. LibreLane's per-corner setup WNS is the worst
    # over ALL clock groups, so 1/(period - WNS) is an Fmax only for a single-clock block.
    clocks = []
    sdc = str(cfg.get("SIGNOFF_SDC_FILE") or cfg.get("PNR_SDC_FILE") or "")
    if sdc.startswith("dir::"):
        sdcp = (ROOT / f"syn/pnr/{top}" / sdc[5:]).resolve()
        if sdcp.is_file():
            clocks = re.findall(r"^\s*create_clock\b.*?-name\s+(\S+)", sdcp.read_text(), re.M)
    multi = len(clocks) > 1
    say(f"# P&R summary: {top}  (LibreLane Classic flow, {cfg.get('PDK','?')} / {cfg.get('STD_CELL_LIBRARY','?')})")
    say(f"run dir            : {run.relative_to(ROOT) if run.is_relative_to(ROOT) else run}")
    say(f"LibreLane exit code: {rc}")
    say(f"final GDS          : {', '.join(p.name for p in gds) if gds else 'MISSING'}")
    if rc != 0 or not gds or not m:
        fails.append(f"flow did not complete (exit {rc}, gds={'yes' if gds else 'no'}, "
                     f"metrics={'yes' if m else 'no'})")

    g = m.get
    say("")
    say("## Area")
    say(f"die area (um^2)        : {fmt(g('design__die__area'))}")
    say(f"core area (um^2)       : {fmt(g('design__core__area'))}")
    say(f"std-cell area (um^2)   : {fmt(g('design__instance__area'))}")
    say(f"std-cell instances     : {fmt(g('design__instance__count'))}")
    say(f"utilization            : {fmt(g('design__instance__utilization'))}")

    say("")
    say("## Power (nominal corner, default activity)")
    for k, label in [("power__total", "total"), ("power__internal__total", "internal"),
                     ("power__switching__total", "switching"), ("power__leakage__total", "leakage")]:
        say(f"{label:<10} (W)        : {fmt(g(k), nd=6)}")

    say("")
    clk = cfg.get("CLOCK_PORT", "?")
    if multi:
        say(f"## Timing ({len(clocks)} clocks in the SDC: {', '.join(clocks)}; WNS = worst over all clock groups)")
        say("Fmax is not derived for a multi-clock block (the worst path may be in any domain);"
            " read the per-clock paths in the stapostpnr reports.")
    else:
        say(f"## Timing (clock {clk}, period {period} ns = {1000/period:.1f} MHz target)" if period else "## Timing")
    corners = sorted({k.split("corner:", 1)[1] for k in m if k.startswith("timing__setup__ws__corner:")})
    hold_bad, setup_bad = [], []
    if not corners:
        say("per-corner timing     : not reported")
        fails.append("no per-corner timing in metrics")
    say(f"{'corner':<24} {'setup WNS':>10} {'setup TNS':>10} {'hold WNS':>10} {'hold TNS':>10} {'Fmax MHz':>9}")
    for c in corners:
        sws, stns = g(f"timing__setup__ws__corner:{c}"), g(f"timing__setup__tns__corner:{c}")
        hws, htns = g(f"timing__hold__ws__corner:{c}"), g(f"timing__hold__tns__corner:{c}")
        fmax = (1000.0 / (period - sws)) if (not multi and period and sws is not None and period - sws > 0) else None
        say(f"{c:<24} {fmt(sws):>10} {fmt(stns):>10} {fmt(hws):>10} {fmt(htns):>10} {('n/a' if multi else fmt(fmax, nd=1)):>9}")
        if hws is not None and hws < 0:
            hold_bad.append(c)
        if sws is not None and sws < 0:
            setup_bad.append((c, fmax))
    if hold_bad:
        fails.append("hold violated at " + ", ".join(hold_bad))

    say("")
    say("## Physical verification / electrical rules")
    drc_keys = ["route__drc_errors", "magic__drc_error__count", "klayout__drc_error__count"]
    for k in drc_keys + ["design__lvs_error__count", "antenna__violating__nets",
                         "design__max_slew_violation__count", "design__max_cap_violation__count",
                         "design__max_fanout_violation__count"]:
        v = g(k)
        say(f"{k:<40}: {fmt(v)}")
    for k in drc_keys:
        if (g(k) or 0) > 0:
            fails.append(f"{k} = {g(k)}")
    if g("design__lvs_error__count") is None:
        fails.append("LVS result not reported")
    elif g("design__lvs_error__count") > 0:
        fails.append(f"LVS errors = {g('design__lvs_error__count')}")
    for k, label in [("antenna__violating__nets", "antenna violating nets"),
                     ("design__max_slew_violation__count", "max-slew violations"),
                     ("design__max_cap_violation__count", "max-cap violations"),
                     ("design__max_fanout_violation__count", "max-fanout violations")]:
        if (g(k) or 0) > 0:
            warns.append(f"{label} = {g(k)} (electrical rule; fix before a real tapeout)")

    say("")
    say("## Verdict")
    setup_gate = os.environ.get("PNR_SETUP_GATE", "0") == "1"
    if setup_bad and setup_gate:
        fails.append(f"setup violated at {', '.join(c for c, _ in setup_bad)} (PNR_SETUP_GATE=1)")
    if setup_bad:
        worst = min(f for _, f in setup_bad if f) if any(f for _, f in setup_bad) else None
        target = (f"the SDC clocks ({', '.join(clocks)})" if multi
                  else f"{period} ns ({1000/period:.0f} MHz)")
        fm = "" if multi else f"; slowest-corner Fmax ~ {fmt(worst, nd=1)} MHz"
        msg = (f"SETUP NOT MET at {target} on "
               f"{', '.join(c for c, _ in setup_bad)}{fm}. "
               + ("Gated (PNR_SETUP_GATE=1)." if setup_gate else "Reported, not gated (PNR_SETUP_GATE=0): the clock budget is the owner's call."))
        warns.append(msg)
    elif corners:
        say(f"setup: MET at {('the SDC clocks' if multi else f'{period} ns')} on all {len(corners)} corners")
    for w in warns:
        say(f"WARNING: {w}")
    for f in fails:
        say(f"FAIL: {f}")
    say(f"RESULT: {'FAIL' if fails else 'PASS'} (flow + DRC + LVS + hold"
        f"{'; setup NOT MET, see above' if setup_bad else ''})")

    text = "\n".join(lines) + "\n"
    rpt.write_text(text)
    print(text)
    for w in warns:
        print(f"::warning title={top} sky130::{w}")
    for f in fails:
        print(f"::error title={top} sky130::{f}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
