#!/usr/bin/env bash
# docker/swarm.sh — run the Claude Code agent swarm on this repo.  [swarm-kit: shared file, do not fork per repo;
#   repo specifics come from .claude/swarm.env - see markrthomas/dv-swarm-kit]
#
#   docker/swarm.sh [--dry-run] [--task FILE | --prompt TEXT] [--model MODEL] [--agent NAME|none]
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
prompt=""
model="${SWARM_MODEL:-}"
agent=""
dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --task) task="$2"; shift ;;
    --prompt) prompt="$2"; shift ;;          # one-off task text instead of a task file (entrypoint `agent` mode)
    --model) model="$2"; shift ;;
    --agent) agent="$2"; shift ;;           # `none` = plain session, no manager agent
    *) echo "swarm.sh: unknown arg $1" >&2; exit 2 ;;
  esac
  shift
done
if [ -z "$prompt" ]; then
  [ -f "$task" ] || { echo "swarm.sh: task file $task not found" >&2; exit 2; }
  prompt="$(cat "$task")"; src="$task"
  if [ -z "$agent" ]; then
    case "$task" in *rr-swarm-task*) agent=rr-manager ;; *) agent=swarm-manager ;; esac
  fi
else
  src="--prompt"; agent="${agent:-none}"
fi
if [ "$agent" != none ]; then
  [ -f ".claude/agents/$agent.md" ] || { echo "swarm.sh: agent $agent not found in .claude/agents" >&2; exit 2; }
fi

cmd=(claude -p "$prompt" --output-format json --permission-mode "${SWARM_PERMISSION_MODE:-acceptEdits}"
     --allowedTools "Read Edit Write Glob Grep Agent")
[ "$agent" != none ] && cmd+=(--agent "$agent")
[ -n "$model" ] && cmd+=(--model "$model")

if [ "$dry" = 1 ]; then
  echo "swarm.sh (dry run): would run in $(pwd) [$PROJECT, envs: ${DV_ENVS:-none}, rr: ${RR_STATUS:-unset}, provider: ${SWARM_MODEL_PROVIDER:-anthropic}]:"
  echo "  claude -p <${#prompt} chars from $src> ${cmd[*]:3}"
  echo "  agents: $(ls .claude/agents/*.md | xargs -n1 basename | tr '\n' ' ')"
  exit 0
fi

command -v claude >/dev/null || { echo "swarm.sh: claude CLI not found (build the image with WITH_CLAUDE=1)" >&2; exit 2; }
. docker/provider-env.sh
swarm_resolve_provider || exit 2

if [ -n "${GITHUB_TOKEN:-}" ]; then   # lets the swarm push a branch / open a draft PR (gh reads GITHUB_TOKEN itself)
  git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
  git config --global user.name  "${GIT_AUTHOR_NAME:-${PROJECT}-swarm}"
  git config --global user.email "${GIT_AUTHOR_EMAIL:-${PROJECT}-swarm@users.noreply.github.com}"
fi

home="$PWD"   # where the caller expects docker/last-run-metrics.json (the swarm workflow uploads it from here)

# A checkout mounted into a container is owned by another uid (the CI runner), and git then refuses it as "dubious
# ownership" - which would look exactly like "no .git" below.  Trust this one directory and carry on.
probe="$(git rev-parse --is-inside-work-tree 2>&1 >/dev/null || true)"   # not a pipe: pipefail would mask the match
case "$probe" in *"dubious ownership"*)
  git config --global --add safe.directory "$PWD"
  echo "swarm.sh: trusting $PWD (checkout owned by another uid)" ;;
esac

# An image built from the repo has no .git (e.g. a Railway swarm service), so nothing could be committed or pushed.
# Clone the repo at run time - on the branch being run, not the default branch - and work there instead.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GH_REPO:-}" ] || {
    echo "swarm.sh: not a git checkout and GITHUB_TOKEN/GH_REPO unset - the swarm could not commit or push" >&2; exit 2; }
  work="${SWARM_WORKDIR:-$HOME/swarm-work}/${PROJECT}"
  rm -rf "$work"; mkdir -p "$(dirname "$work")"
  ref="${SWARM_REF:-${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-}}}"
  git clone -q --depth 50 ${ref:+--branch "$ref"} "https://github.com/${GH_REPO}.git" "$work"
  echo "swarm.sh: image has no .git - cloned ${GH_REPO}${ref:+@$ref} into $work"
  cd "$work"
fi

# Headless Claude Code ignores the repo's .claude/settings.json allow list ("this workspace has not been trusted")
# until the trust dialog has been accepted once - which never happens in a fresh container, so every `make` was
# denied.  Running the swarm on this checkout is the trust decision: record it for this exact path only.
python3 - "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" "$PWD" <<'TRUST'
import json, os, sys
path, repo = sys.argv[1], sys.argv[2]
try:
    cfg = json.load(open(path))
except (OSError, ValueError):
    cfg = {}
cfg.setdefault("projects", {}).setdefault(repo, {})["hasTrustDialogAccepted"] = True
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
json.dump(cfg, open(path, "w"), indent=1)
TRUST
echo "swarm.sh: workspace trusted for this headless run: $PWD (the .claude/settings.json allow list applies)"

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
[ "$PWD" != "$home" ] && mkdir -p "$home/docker" && cp -f docker/last-run-metrics.json "$home/docker/"
echo "swarm.sh: claude exited $rc; usage -> $home/docker/last-run-metrics.json"
# the manager's final report, in the job log too (the artifact holds the same text plus token usage)
echo "===== swarm report (last 4000 chars) ====="
python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("result") or "(no result - see the claude output above)")' docker/last-run-metrics.json || true
exit "$rc"
