# docker/profile.sh — source me: load .claude/swarm.env (the repo profile) WITHOUT overriding variables that are
# already set, so a Railway service variable / GitHub secret / shell export always beats the profile default.
# [swarm-kit: shared file, do not fork per repo]
# Records which keys came from the environment in SWARM_ENV_OVERRIDES (space separated).
SWARM_ENV_OVERRIDES=""
if [ -f .claude/swarm.env ]; then
  while IFS= read -r _line; do
    _k="${_line%%=*}"
    if [ -n "${!_k+x}" ]; then
      SWARM_ENV_OVERRIDES="$SWARM_ENV_OVERRIDES $_k"
    else
      eval "export $_line"
    fi
  done < <(grep -E '^[A-Z][A-Z0-9_]*=' .claude/swarm.env)
  unset _line _k
fi
export SWARM_ENV_OVERRIDES
