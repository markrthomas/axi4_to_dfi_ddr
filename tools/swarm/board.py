#!/usr/bin/env python3
"""Swarm status board: how a manager tracks workers that live in other sandboxes (cloud sessions).

Workers can only talk through git.  Each worker owns ONE file on ITS OWN branch,
$RR_DIR/board/<worker>.json, so boards never conflict.  The manager reads every worker's file
straight from `origin/swarm/*` without checking anything out.

Worker side (run at every milestone, then `git push`; the command commits for you):
    board.py start   NAME --task "B1/B2 harness stimulus" [--steps 5]
    board.py update  NAME --step 2 --msg "B1 done, building rand scenario"   [--blocker TXT]
    board.py result  NAME --jobs 200 --fails 3 --clusters 2 [--note TXT]
    board.py done    NAME --msg "final report in PR/branch notes"   (state=done)
    board.py fail    NAME --msg "why it stopped"                    (state=blocked)

Manager side:
    board.py show [--stale-min 30] [--brief] [--active] [--json]   fetch + table of workers; --brief = 1 line each, --active hides done/retired
    board.py retire NAME                      hide a finished/legacy worker from --active
    board.py assign NAME --task TXT [--branch swarm/NAME]   register planned work in board/tasks.json
    board.py wait [--timeout-min 60] [--every 120]   block until every assigned worker is done/blocked

State machine: assigned -> running -> (blocked | done).  A worker whose last update is older than
--stale-min while `running` is shown as STALE (crashed, hung, or forgot to update).
"""
import argparse
import datetime
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# swarm-kit: the board lives in $RR_DIR/board (from .claude/swarm.env), so the same script works in
# every repo whatever its DV layout.  board.py itself is shared; run it from anywhere in the repo.
ROOT = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True).stdout.strip() or os.path.abspath(os.path.join(HERE, "..", ".."))


def _profile(key, default):
    try:
        for line in open(os.path.join(ROOT, ".claude", "swarm.env")):
            k, _, v = line.split("#", 1)[0].strip().partition("=")
            if k == key and v:
                return v.strip().strip('"').strip("'")
    except OSError:
        pass
    return default


BOARD = os.path.join(ROOT, _profile("RR_DIR", "dv/random"), "board")
REL = os.path.relpath(BOARD, ROOT)
TASKS = os.path.join(BOARD, "tasks.json")


def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)


def git(*a, check=True):
    return subprocess.run(["git", "-C", ROOT, *a], capture_output=True, text=True, check=check).stdout


def path(name):
    return os.path.join(BOARD, f"{name}.json")


def load(name):
    p = path(name)
    return json.load(open(p)) if os.path.exists(p) else {"worker": name, "state": "running", "history": []}


def write(name, d, msg):
    os.makedirs(BOARD, exist_ok=True)
    d["updated"] = now().isoformat()
    try:
        d["branch"] = git("rev-parse", "--abbrev-ref", "HEAD").strip()
        d["sha"] = git("rev-parse", "--short", "HEAD").strip()
    except Exception:
        pass
    d.setdefault("history", []).append({"t": d["updated"], "state": d["state"], "step": d.get("step"), "msg": msg})
    d["history"] = d["history"][-30:]
    json.dump(d, open(path(name), "w"), indent=1)
    open(path(name), "a").write("\n")
    git("add", os.path.relpath(path(name), ROOT), check=False)
    git("commit", "-q", "-m", f"board({name}): {d['state']} step {d.get('step')} - {msg}", check=False)
    print(f"board: {name} {d['state']} step={d.get('step')}/{d.get('steps')} - {msg}  (now `git push`)")


def cmd_worker(a):
    d = load(a.name)
    if a.cmd == "start":
        d.update(state="running", task=a.task, steps=a.steps, step=0)
        write(a.name, d, "started")
    elif a.cmd == "update":
        d["state"] = "running"
        if a.step is not None:
            d["step"] = a.step
        d["blocker"] = a.blocker or ""
        write(a.name, d, a.msg)
    elif a.cmd == "result":
        d["results"] = {"jobs": a.jobs, "fails": a.fails, "clusters": a.clusters, "note": a.note or ""}
        write(a.name, d, f"result jobs={a.jobs} fails={a.fails} clusters={a.clusters}")
    elif a.cmd in ("done", "fail"):
        d["state"] = "done" if a.cmd == "done" else "blocked"
        if a.cmd == "done" and d.get("steps"):
            d["step"] = d["steps"]
        write(a.name, d, a.msg)
    return 0


def cmd_assign(a):
    os.makedirs(BOARD, exist_ok=True)
    t = json.load(open(TASKS)) if os.path.exists(TASKS) else {}
    t[a.name] = {"task": a.task, "branch": a.branch or f"swarm/{a.name}", "assigned": now().isoformat()}
    json.dump(t, open(TASKS, "w"), indent=1)
    open(TASKS, "a").write("\n")
    git("add", os.path.relpath(TASKS, ROOT))
    git("commit", "-q", "-m", f"board: assign {a.name}")
    print(f"assigned {a.name} -> {t[a.name]['branch']}")
    return 0


def remote_boards():
    """worker -> board dict, read from every origin branch (no checkout)."""
    git("fetch", "-q", "origin", check=False)
    out = {}
    for ref in git("for-each-ref", "--format=%(refname:short)", "refs/remotes/origin/swarm/").split():
        files = git("ls-tree", "--name-only", ref, f"{REL}/", check=False).split()
        for f in files:
            if f.endswith("tasks.json") or not f.endswith(".json"):
                continue
            try:
                d = json.loads(git("show", f"{ref}:{f}"))
            except Exception:
                continue
            d["_ref"], d["_ref_sha"] = ref, git("rev-parse", "--short", ref).strip()
            prev = out.get(d["worker"])
            if not prev or d.get("updated", "") > prev.get("updated", ""):
                out[d["worker"]] = d
    return out


def table(stale_min):
    boards = remote_boards()
    tasks = json.load(open(TASKS)) if os.path.exists(TASKS) else {}
    rows = []
    for name in sorted(set(boards) | set(tasks)):
        d = boards.get(name)
        if not d:
            rows.append({"worker": name, "state": "NO_REPORT", "task": tasks[name]["task"], "age_min": None})
            continue
        age = (now() - datetime.datetime.fromisoformat(d["updated"])).total_seconds() / 60
        state = "STALE" if d["state"] == "running" and age > stale_min else d["state"]
        r = d.get("results") or {}
        rows.append({"worker": name, "state": state, "step": f"{d.get('step')}/{d.get('steps')}",
                     "age_min": round(age), "ref": f"{d['_ref']}@{d['_ref_sha']}", "task": d.get("task", ""),
                     "last": d["history"][-1]["msg"] if d.get("history") else "",
                     "blocker": d.get("blocker", ""),
                     "results": f"jobs={r.get('jobs')} fails={r.get('fails')} clusters={r.get('clusters')}" if r else ""})
    return rows


def cmd_retire(a):
    t = json.load(open(TASKS))
    t[a.name]["retired"] = True
    json.dump(t, open(TASKS, "w"), indent=1)
    open(TASKS, "a").write("\n")
    git("add", os.path.relpath(TASKS, ROOT))
    git("commit", "-q", "-m", f"board: retire {a.name}")
    print(f"retired {a.name} (hidden from --active)")
    return 0


def cmd_show(a):
    rows = table(a.stale_min)
    tasks = json.load(open(TASKS)) if os.path.exists(TASKS) else {}
    if a.active:   # live workers only: not done, not retired
        rows = [r for r in rows if r["state"] != "done" and not tasks.get(r["worker"], {}).get("retired")]
    if a.brief:    # one short line per worker (cheapest for polling)
        for r in rows:
            last = (r.get("last") or r["task"])[:80]
            print(f"{r['worker']} {r['state']} {r.get('step', '-')} {r['age_min']}m {last}")
        if not rows:
            print("board: no active workers")
        return 0
    if a.json:
        print(json.dumps(rows, indent=1))
        return 0
    if not rows:
        print("board: no workers reported or assigned")
    for r in rows:
        print(f"{r['worker']:14} {r['state']:9} step {r.get('step', '-'):>5} age {str(r['age_min']) + 'm':>6}  {r.get('ref', '')}")
        print(f"{'':14} task: {r['task']}")
        for k in ("last", "blocker", "results"):
            if r.get(k):
                print(f"{'':14} {k}: {r[k]}")
    open_ = [r for r in rows if r["state"] not in ("done",)]
    print(f"board: {len(rows) - len(open_)}/{len(rows)} done; attention: "
          + (", ".join(f"{r['worker']}={r['state']}" for r in open_ if r["state"] in ("STALE", "blocked", "NO_REPORT")) or "none"))
    return 0


def cmd_wait(a):
    end = time.time() + a.timeout_min * 60
    while time.time() < end:
        rows = table(a.stale_min)
        if rows and all(r["state"] in ("done", "blocked", "STALE") for r in rows):
            return cmd_show(argparse.Namespace(stale_min=a.stale_min, json=False))
        time.sleep(a.every)
    print("board: wait timed out")
    return cmd_show(argparse.Namespace(stale_min=a.stale_min, json=False)) or 2


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    for c in ("start", "update", "result", "done", "fail"):
        p = sp.add_parser(c)
        p.add_argument("name")
        p.add_argument("--task", default="")
        p.add_argument("--steps", type=int, default=0)
        p.add_argument("--step", type=int)
        p.add_argument("--msg", default=c)
        p.add_argument("--blocker")
        p.add_argument("--jobs", type=int)
        p.add_argument("--fails", type=int)
        p.add_argument("--clusters", type=int)
        p.add_argument("--note")
    s = sp.add_parser("show")
    s.add_argument("--stale-min", type=int, default=30)
    s.add_argument("--json", action="store_true")
    s.add_argument("--brief", action="store_true", help="one short line per worker")
    s.add_argument("--active", action="store_true", help="hide done / retired workers")
    rt = sp.add_parser("retire")
    rt.add_argument("name")
    w = sp.add_parser("wait")
    w.add_argument("--timeout-min", type=int, default=60)
    w.add_argument("--every", type=int, default=120)
    w.add_argument("--stale-min", type=int, default=30)
    g = sp.add_parser("assign")
    g.add_argument("name")
    g.add_argument("--task", required=True)
    g.add_argument("--branch")
    a = ap.parse_args()
    if a.cmd in ("start", "update", "result", "done", "fail"):
        return cmd_worker(a)
    return {"show": cmd_show, "wait": cmd_wait, "assign": cmd_assign, "retire": cmd_retire}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
