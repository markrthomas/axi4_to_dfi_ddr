#!/usr/bin/env bash
# docker/entrypoint.sh — container entrypoint (Railway batch job / Codespaces / local run).
# [swarm-kit: shared file, do not fork per repo; repo specifics come from .claude/swarm.env]
#   (no args) | ci : the repo's full batch, then publish the results to the `metrics-data` branch:
#                      METRICS=yes -> make metrics (+ CROSSCHECK_TARGET) + make dashboard
#                      otherwise   -> make $CI_TARGET, log kept in logs/batch.log
#                    exit non-zero if anything failed
#   swarm [args]   : run the agent swarm (docker/swarm.sh; needs CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY)
#   <cmd...>       : run an arbitrary command inside the image
set -euo pipefail
# the image keeps the repo at /repo; outside the image (a checkout / Codespace) use the checkout this script lives in
if [ -d /repo ] && [ -f /repo/.claude/swarm.env ]; then cd /repo; else cd "$(dirname "$0")/.."; fi
. docker/profile.sh
CI_TARGET="${CI_TARGET:-ci}"

# Build parallelism.  DV Makefiles often default to `JOBS ?= $(nproc)`, and in a container nproc reports the
# HOST's cores while the memory limit is a few GB: a UVM / Verilator build then runs that many g++ jobs at once
# and the container thrashes or is killed.  Unless JOBS is set, derive it from the cgroup memory limit
# (about 3 GB per job), capped by the visible cores.
if [ -z "${JOBS:-}" ]; then
  cores="$(nproc 2>/dev/null || echo 4)"
  lim="$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo max)"
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

mode="${1:-ci}"
case "$mode" in
  ci)
    rc=0
    mkdir -p logs
    if [ "${METRICS:-no}" = "yes" ] && [ -f metrics/collect.py ]; then
      # METRICS_FLOWS default comes from swarm.env; a Railway variable overrides it
      make metrics METRICS_FLOWS="${METRICS_FLOWS:-$CI_TARGET}" METRICS_NOTE="${METRICS_NOTE:-container run}" || rc=$?
      # a cross-check needs every env; with a reduced METRICS_FLOWS it would always fail, so it runs only
      # for the profile's default flow list or RUN_CROSSCHECK=1
      if [ -n "${CROSSCHECK_TARGET:-}" ] && { [ "${RUN_CROSSCHECK:-}" = "1" ] || [[ " $SWARM_ENV_OVERRIDES " != *" METRICS_FLOWS "* ]]; }; then
        make "$CROSSCHECK_TARGET" || rc=$?
      fi
      make dashboard || rc=$?
    else
      echo "entrypoint: make $CI_TARGET (log: logs/batch.log)"
      make "$CI_TARGET" 2>&1 | tee logs/batch.log || rc=$?     # pipefail: rc is make's status
    fi
    # the container is ephemeral: publish the results to the repo's metrics-data branch (docs/railway.md);
    # a publishing problem is reported but does not change the run's exit code
    # PUBLISH_METRICS: unset = publish when a token is available (Railway); 1 = publish; empty or 0 = don't
    # (the Codespace sets 0, an Actions batch with publish unticked passes '')
    case "${PUBLISH_METRICS-auto}" in
      ""|0) echo "entrypoint: publishing off (PUBLISH_METRICS='${PUBLISH_METRICS}')" ;;
      *)    docker/publish_metrics.sh "$rc" || echo "entrypoint: WARNING: publishing the results failed (see above)" ;;
    esac
    echo "entrypoint: done (rc=$rc)"
    exit "$rc"
    ;;
  swarm)
    shift
    exec docker/swarm.sh "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
