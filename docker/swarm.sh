#!/usr/bin/env bash
# docker/swarm.sh — run the Claude Code agent swarm on this repo.  [swarm-kit: shared file, do not fork per repo;
#   repo specifics come from .claude/swarm.env - see markrthomas/dv-swarm-kit]
#
#   docker/swarm.sh [--dry-run] [--task FILE] [--model MODEL] [--agent NAME]
#
# Runs Claude Code non-interactively (-p) and NON-bare, so the project's
# .claude/agents/ definitions are discoverable; the task (default
# docker/swarm-task.md) tells the manager what to dispatch. The top-level session runs AS the
# manager agent (--agent; default swarm-manager, rr-manager for rr-swarm-task.md), so it keeps the
# Agent tool and can dispatch workers (sub-agents cannot spawn sub-agents). Bash is NOT in
# --allowedTools: only the commands in .claude/settings.json's allow list run headless, and its
# deny rules (force-push, push to main, ...) always apply. Add a pattern there if a worker needs more.
# Needs: `claude` on PATH (npm i -g @anthropic-ai/claude-code; the image has it
# when built with --build-arg WITH_CLAUDE=1), a credential in the environment -
# CLAUDE_CODE_OAUTH_TOKEN (what the Railway service uses; the Claude Code CLI reads it
# itself) or ANTHROPIC_API_KEY (or another provider via ANTHROPIC_BASE_URL +
# ANTHROPIC_AUTH_TOKEN, e.g. an Anthropic-compatible endpoint) - never put it in the
# repo or the image: set it as a Railway service variable / GitHub secret; and optionally GITHUB_TOKEN so it can push a
# branch / open a draft PR.  A human merges.
# Writes docker/last-run-metrics.json (tokens per model, from the CLI's JSON
# output) for metrics/collect.py.  Per-agent token split is not available from
# the CLI output, so the agent column is recorded as "all".
set -euo pipefail
cd "$(dirname "$0")/.."
# repo profile (PROJECT, DV_ENVS, ...): exported so the agents' Bash sees the same values; env vars win
. docker/profile.sh
PROJECT="${PROJECT:-$(basename "$PWD")}"

task=docker/swarm-task.md
model="${SWARM_MODEL:-}"
agent=""
dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --task) task="$2"; shift ;;
    --model) model="$2"; shift ;;
    --agent) agent="$2"; shift ;;
    *) echo "swarm.sh: unknown arg $1" >&2; exit 2 ;;
  esac
  shift
done
[ -f "$task" ] || { echo "swarm.sh: task file $task not found" >&2; exit 2; }

if [ -z "$agent" ]; then
  case "$task" in *rr-swarm-task*) agent=rr-manager ;; *) agent=swarm-manager ;; esac
fi
[ -f ".claude/agents/$agent.md" ] || { echo "swarm.sh: agent $agent not found in .claude/agents" >&2; exit 2; }

cmd=(claude -p "$(cat "$task")" --agent "$agent" --output-format json --permission-mode acceptEdits
     --allowedTools "Read Edit Write Glob Grep Agent")
[ -n "$model" ] && cmd+=(--model "$model")

if [ "$dry" = 1 ]; then
  echo "swarm.sh (dry run): would run in $(pwd) [$PROJECT, envs: ${DV_ENVS:-none}, rr: ${RR_STATUS:-unset}]:"
  printf '  %q' "${cmd[@]:0:1}"; echo " -p <$(wc -c < "$task") bytes from $task> ${cmd[*]:3}"
  echo "  agents: $(ls .claude/agents/*.md | xargs -n1 basename | tr '\n' ' ')"
  exit 0
fi

command -v claude >/dev/null || { echo "swarm.sh: claude CLI not found" >&2; exit 2; }
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  echo "swarm.sh: set CLAUDE_CODE_OAUTH_TOKEN (or ANTHROPIC_API_KEY, or ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN)" >&2
  exit 2
fi

if [ -n "${GITHUB_TOKEN:-}" ]; then   # lets the swarm push a branch / open a draft PR
  git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
  git config --global user.name  "${GIT_AUTHOR_NAME:-${PROJECT}-swarm}"
  git config --global user.email "${GIT_AUTHOR_EMAIL:-${PROJECT}-swarm@users.noreply.github.com}"
fi

out=$(mktemp)
rc=0
"${cmd[@]}" > "$out" || rc=$?
python3 - "$out" "$rc" > docker/last-run-metrics.json <<'PY'
import json, sys
path, rc = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(path))
except Exception:
    d = {}
rows = []
for model, u in (d.get("modelUsage") or {}).items():
    tok = sum(u.get(k, 0) for k in ("inputTokens", "outputTokens", "cacheReadInputTokens", "cacheCreationInputTokens"))
    rows.append({"agent": "all", "model": model, "tokens": tok, "status": "PASS" if rc == 0 else "FAIL"})
json.dump({"rc": rc, "agents": rows, "total_cost_usd": d.get("total_cost_usd"),
           "result": (d.get("result") or "")[-4000:]}, sys.stdout, indent=2)
PY
echo "swarm.sh: claude exited $rc; usage -> docker/last-run-metrics.json"
exit "$rc"
