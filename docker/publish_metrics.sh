#!/usr/bin/env bash
# docker/publish_metrics.sh [RC] — publish this container run's results to the `metrics-data` branch
# of the GitHub repo, so they outlive the (ephemeral) Railway container and can be pulled into the
# dashboard with `make railway-import`.  Called by docker/entrypoint.sh (ci mode) after the run.
#
# Layout on the branch (an orphan branch holding no source):
#   runs/<UTC>-<sha7>/{run.json, metrics.db, dashboard.html | batch.log}   one directory per run (never rewritten)
#   latest/{...}                                              copy of the newest run
# run.json holds only non-secret run facts (time, commit, Railway service / environment / deployment
# ids from the RAILWAY_* variables Railway injects, exit code).
#
# Needs GITHUB_TOKEN (a fine-grained token limited to THIS repo, Contents: read+write) as a Railway
# service variable.  Without it this prints a notice and exits 0 (results stay in the container).
# The token is passed to git as an http header: it is never put in a URL, a git config file or the log.
# What is published: metrics/metrics.db + metrics/dashboard.html when the repo has the metrics flow (METRICS=yes),
# otherwise the tail of logs/batch.log; plus docker/last-run-metrics.json after a swarm run.
# [swarm-kit: shared file, do not fork per repo; repo specifics come from .claude/swarm.env]
# Env: PUBLISH_REPO (owner/name; default GH_REPO from the profile), PUBLISH_BRANCH (default metrics-data), PUBLISH_URL (override, tests).
set -euo pipefail
cd "$(dirname "$0")/.."
. docker/profile.sh
src="$PWD"
rc="${1:-0}"
repo="${PUBLISH_REPO:-${GH_REPO:?set GH_REPO in .claude/swarm.env or PUBLISH_REPO}}"
branch="${PUBLISH_BRANCH:-metrics-data}"
url="${PUBLISH_URL:-https://github.com/${repo}.git}"

if [ -z "${GITHUB_TOKEN:-}" ] && [ -z "${PUBLISH_URL:-}" ]; then
  echo "publish: GITHUB_TOKEN not set - results stay in the container (see docs/railway.md)"
  exit 0
fi
files=()
if [ "${METRICS:-no}" = "yes" ]; then
  for f in metrics/metrics.db metrics/dashboard.html; do
    [ -f "$f" ] || { echo "publish: $f missing - nothing to publish" >&2; exit 1; }
    files+=("$f")
  done
fi
[ -f logs/batch.log ] && files+=(logs/batch.log)
[ -f docker/last-run-metrics.json ] && files+=(docker/last-run-metrics.json)
[ "${#files[@]}" -gt 0 ] || { echo "publish: no results found - nothing to publish" >&2; exit 1; }

hdr=""
[ -n "${GITHUB_TOKEN:-}" ] && hdr="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)"
g() { if [ -n "$hdr" ]; then command git -c "http.extraheader=$hdr" "$@"; else command git "$@"; fi; }

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sha="$(git rev-parse --short HEAD 2>/dev/null || echo "${RAILWAY_GIT_COMMIT_SHA:0:7}")"
dir="runs/$(date -u +%Y%m%dT%H%M%SZ)-${sha:-unknown}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

if g ls-remote --exit-code --heads "$url" "$branch" >/dev/null 2>&1; then
  g clone -q --depth 1 --branch "$branch" "$url" "$work/repo"
else
  command git init -q "$work/repo"
  command git -C "$work/repo" checkout -q --orphan "$branch"
fi
cd "$work/repo"
git config user.name  "${GIT_AUTHOR_NAME:-${PROJECT:-dv}-railway}"
git config user.email "${GIT_AUTHOR_EMAIL:-${PROJECT:-dv}-railway@users.noreply.github.com}"

mkdir -p "$dir" latest
python3 - "$dir/run.json" "$ts" "$sha" "$rc" <<'PY'
import json, os, sys
out, ts, sha, rc = sys.argv[1:5]
env = os.environ.get
json.dump({"ts_utc": ts, "git_sha": sha, "exit_code": int(rc),
           "service": env("RAILWAY_SERVICE_NAME") or "local",
           "environment": env("RAILWAY_ENVIRONMENT_NAME") or "",
           "deployment_id": env("RAILWAY_DEPLOYMENT_ID") or "",
           "note": env("METRICS_NOTE") or ""}, open(out, "w"), indent=1)
PY
for f in "${files[@]}"; do
  case "$f" in logs/batch.log) tail -n 3000 "$src/$f" > "$dir/batch.log" ;; *) cp "$src/$f" "$dir/" ;; esac
done
rm -rf latest && mkdir latest && cp "$dir"/* latest/
git add -A
git commit -q -m "metrics: run ${ts} ${sha} rc=${rc}"

for attempt in 1 2 3 4; do
  if g push -q "$url" "HEAD:refs/heads/${branch}" 2>/dev/null; then
    echo "publish: pushed ${dir} to ${branch}"; exit 0
  fi
  echo "publish: push rejected (attempt ${attempt}); rebasing"
  # a concurrent writer: put our commit on top of theirs (on a conflict, in latest/, ours wins)
  if g fetch -q "$url" "$branch"; then git rebase -q -X theirs FETCH_HEAD || git rebase --abort || true; fi
  sleep $((attempt * 2))
done
echo "publish: could not push to ${branch}" >&2
exit 1
