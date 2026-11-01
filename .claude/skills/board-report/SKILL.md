---
name: board-report
description: How a swarm worker reports status on the git-based board and formats its final answer. Use at the start, at each milestone and at the end of any swarm task in this repo.
---
Workers talk to the manager only through git. Your status lives in one file on your own branch,
`$RR_DIR/board/<worker>.json` (`RR_DIR` from `.claude/swarm.env`); `tools/swarm/board.py` writes and commits it for you.

Run from the repo root, with NAME = your worker name, at start, each milestone and the end, then `git push`:

```
python3 tools/swarm/board.py start  NAME --task "<one line>" [--steps N]
python3 tools/swarm/board.py update NAME --step K --msg "<what just finished>" [--blocker TXT]
python3 tools/swarm/board.py result NAME --jobs J --fails F --clusters C [--note TXT]   # regression batches only
python3 tools/swarm/board.py done   NAME --msg "<where the final report is>"
python3 tools/swarm/board.py fail   NAME --msg "<why you stopped>"                      # state = blocked
```

- The board commit is the only write read-only agents (runner, triage) may make; they edit no source.
- Push only your `swarm/<topic>` branch. Never `main`, never force.
- A worker with no update for 30 minutes shows as STALE to the manager, so update before long runs.

Final answer format (same as CLAUDE.md, repeated here because it is what the manager parses):
**verdict**, **evidence** (file:line, or command plus a 3-10 line excerpt), **next step**. Cite log paths,
never paste full logs. Say "not run" and why for anything you skipped.
