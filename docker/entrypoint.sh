#!/usr/bin/env bash
# docker/entrypoint.sh — container entrypoint (Railway batch job / Codespaces / local run).
# [swarm-kit: shared file, do not fork per repo; repo specifics come from .claude/swarm.env]
#   (no args) | ci   : the repo's full batch, then publish the results to the `metrics-data` branch:
#                        METRICS=yes -> make metrics (+ CROSSCHECK_TARGET) + make dashboard
#                        otherwise   -> make $CI_TARGET $MAKE_OVERRIDES, full log kept in logs/batch.log
#                      exit non-zero if anything failed
#   make <targets>   : make <targets> $MAKE_OVERRIDES (same log trimming / preflight as ci)
#   swarm [args]     : the agent swarm (docker/swarm.sh; credentials: docker/provider-env.sh)
#   agent "<task>"   : one headless Claude Code session on a one-off task (no manager agent)
#   shell            : interactive shell, or (no TTY) hold the container open for `railway ssh`
#   <cmd...>         : run an arbitrary command inside the image
# Knobs (Railway variables / env; profile defaults in .claude/swarm.env):
#   MAKE_OVERRIDES   extra make args for bundled tools, e.g. "VERILATOR=/opt/verilator/bin/verilator UVM_HOME=..."
#   MIN_MEM_MB       memory floor checked before CI_TARGET / HEAVY_TARGETS (fail fast, exit 3, instead of an
#                    OOM-killed cc1plus);
#                    SKIP_MEM_CHECK=1 bypasses it
#   LOG_QUIET        1 = stream only signal lines ([BANNER]s, errors, warnings, PASS/FAIL) and keep the full
#                    transcript in logs/batch.log (default: on when running on Railway, which rate-limits logs)
#   KEEP_ALIVE=1     after the batch, hold the container open (railway ssh in to inspect)
#   DEBUG_SHELL=1    skip the batch and hold the container open
#   POST_BATCH       shell command run after the batch (e.g. "make metrics dashboard"); additive - it cannot change
#                    the batch's exit code
#   PUBLISH_METRICS  unset = publish when a token is set (Railway); 1 = publish; empty or 0 = don't
# Ported from eth-dj-to-pcie-pipe-bridge, axi-on-ucie-to-mem and ucie2-pipe7-bridge.
set -euo pipefail
# the image keeps the repo at /repo or /work; a checkout mounted at /repo (swarm workflow) wins
if [ -d /repo ] && [ -f /repo/.claude/swarm.env ]; then cd /repo; else cd "$(dirname "$0")/.."; fi
. docker/profile.sh
CI_TARGET="${CI_TARGET:-ci}"
read -r -a overrides <<< "${MAKE_OVERRIDES:-}"

# Build parallelism.  DV Makefiles often default to `JOBS ?= $(nproc)`, and in a container nproc reports the
# HOST's cores while the memory limit is a few GB: a UVM / Verilator build then runs that many g++ jobs at once
# and the container thrashes or is killed.  Unless JOBS is set, derive it from the cgroup memory limit
# (about 3 GB per job), capped by the visible cores.
mem_limit() { cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo max; }
if [ -z "${JOBS:-}" ]; then
  cores="$(nproc 2>/dev/null || echo 4)"
  lim="$(mem_limit)"
  if [ "$lim" != "max" ] && [ "$lim" -lt 1099511627776 ] 2>/dev/null; then
    jobs=$(( lim / 1073741824 / 3 ))
  else
    jobs=4                                   # no (usable) memory limit visible
  fi
  [ "$jobs" -lt 1 ] && jobs=1
  [ "$jobs" -gt "$cores" ] && jobs="$cores"
  export JOBS="$jobs"
  echo "entrypoint: JOBS=$JOBS (cores=$cores, memory limit=$lim; set JOBS to override)"
fi

preflight() {   # preflight <targets...>: fail fast before a RAM-heavy build that would only be OOM-killed minutes in
  [ -n "${MIN_MEM_MB:-}" ] && [ "${SKIP_MEM_CHECK:-0}" != 1 ] || return 0
  local t heavy=0 lim mb      # only the batch target and HEAVY_TARGETS are guarded; `make lint` on a small box is fine
  for t in "$@"; do [[ " $CI_TARGET ${HEAVY_TARGETS:-} " == *" $t "* ]] && heavy=1; done
  [ "$heavy" = 1 ] || return 0
  lim="$(mem_limit)"
  if [ "$lim" = max ] || ! [ "$lim" -lt 1099511627776 ] 2>/dev/null; then
    mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
  else
    mb=$(( lim / 1048576 ))
  fi
  echo "[preflight] memory ${mb} MB (floor ${MIN_MEM_MB} MB), vCPUs $(nproc 2>/dev/null || echo ?), JOBS=${JOBS}"
  if [ "$mb" -gt 0 ] && [ "$mb" -lt "$MIN_MEM_MB" ]; then
    echo "[preflight] ERROR: below the ${MIN_MEM_MB} MB floor - raise the instance memory (Railway: Settings ->" >&2
    echo "[preflight]   Resource Limits) or set SKIP_MEM_CHECK=1 to bypass." >&2
    return 1
  fi
}

# Railway rate-limits log ingestion; a Verilator-heavy gate (one ~500-char g++ line per source file) blows through it
# and buries the banners.  Quiet mode streams only signal lines and keeps the full transcript in logs/batch.log,
# tail-dumped on failure.  The exit status is always make's, never grep's.
if [ -z "${LOG_QUIET:-}" ]; then
  LOG_QUIET=0; [ -n "${RAILWAY_SERVICE_ID:-}${RAILWAY_PROJECT_ID:-}${RAILWAY_ENVIRONMENT:-}" ] && LOG_QUIET=1
fi
SIGNAL_RE="${LOG_SIGNAL_RE:-(\[[A-Z][A-Za-z0-9_ -]+\])|([Ee]rror)|([Ww]arning)|(%Error)|(%Warning)|(PASS)|(FAIL)|(\bsorry:)|(Assertion)|(\\\$finish)|(make(\[[0-9]+\])?: \*\*\*)}"
run_make() {    # run_make <targets...>; returns make's status; full log in logs/batch.log
  mkdir -p logs
  local rc=0
  if [ "$LOG_QUIET" = 1 ]; then
    set +e
    make "$@" "${overrides[@]}" 2>&1 | tee logs/batch.log | grep --line-buffered -E "$SIGNAL_RE"
    rc=${PIPESTATUS[0]}
    set -e
    if [ "$rc" -ne 0 ]; then echo "=== make $* FAILED (rc=$rc) - last 200 lines of logs/batch.log ==="; tail -n 200 logs/batch.log; fi
  else
    make "$@" "${overrides[@]}" 2>&1 | tee logs/batch.log || rc=$?     # pipefail: rc is make's status
  fi
  return "$rc"
}

hold_open() { echo "entrypoint: holding the container open ($1) - attach with \`railway ssh\`"; exec sleep infinity; }

mode="${1:-ci}"
case "$mode" in
  ci)
    [ "${DEBUG_SHELL:-0}" = 1 ] && hold_open "DEBUG_SHELL=1, batch skipped"
    rc=0
    preflight "$CI_TARGET" || exit 3
    if [ "${METRICS:-no}" = "yes" ]; then
      # METRICS_FLOWS default comes from swarm.env; a Railway variable overrides it
      make metrics METRICS_FLOWS="${METRICS_FLOWS:-$CI_TARGET}" METRICS_NOTE="${METRICS_NOTE:-container run}" "${overrides[@]}" || rc=$?
      # a cross-check needs every env; with a reduced METRICS_FLOWS it would always fail, so it runs only
      # for the profile's default flow list or RUN_CROSSCHECK=1
      if [ -n "${CROSSCHECK_TARGET:-}" ] && { [ "${RUN_CROSSCHECK:-}" = "1" ] || [[ " $SWARM_ENV_OVERRIDES " != *" METRICS_FLOWS "* ]]; }; then
        make "$CROSSCHECK_TARGET" "${overrides[@]}" || rc=$?
      fi
      make dashboard || rc=$?
    else
      echo "entrypoint: make $CI_TARGET ${MAKE_OVERRIDES:-} (full log: logs/batch.log)"
      run_make "$CI_TARGET" || rc=$?
    fi
    if [ -n "${POST_BATCH:-}" ]; then
      echo "entrypoint: POST_BATCH: ${POST_BATCH} (additive: cannot change rc=$rc)"
      bash -c "$POST_BATCH" || echo "entrypoint: POST_BATCH failed (ignored)"
    fi
    # the container is ephemeral: publish the results to the repo's metrics-data branch;
    # a publishing problem is reported but does not change the run's exit code
    case "${PUBLISH_METRICS-auto}" in
      ""|0) echo "entrypoint: publishing off (PUBLISH_METRICS='${PUBLISH_METRICS}')" ;;
      *)    docker/publish_metrics.sh "$rc" || echo "entrypoint: WARNING: publishing the results failed (see above)" ;;
    esac
    echo "entrypoint: done (rc=$rc)"
    [ "${KEEP_ALIVE:-0}" = 1 ] && hold_open "KEEP_ALIVE=1, batch rc=$rc"
    exit "$rc"
    ;;
  make)
    shift
    preflight "$@" || exit 3
    rc=0; run_make "$@" || rc=$?
    [ "${KEEP_ALIVE:-0}" = 1 ] && hold_open "KEEP_ALIVE=1, make rc=$rc"
    exit "$rc"
    ;;
  swarm)
    shift
    exec docker/swarm.sh "$@"
    ;;
  agent|claude)
    shift
    task="${*:-${CLAUDE_TASK:-}}"
    [ -n "$task" ] || { [ ! -t 0 ] && task="$(cat)"; }
    [ -n "$task" ] || { echo "entrypoint: agent needs a task (argument, CLAUDE_TASK, or stdin)" >&2; exit 2; }
    exec docker/swarm.sh --prompt "$task" --agent none
    ;;
  shell)
    if [ -t 0 ]; then exec bash -l; else hold_open "shell requested, no TTY"; fi
    ;;
  *)
    exec "$@"
    ;;
esac
