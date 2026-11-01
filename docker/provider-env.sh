# docker/provider-env.sh — source me: pick the model provider for a headless Claude Code run.
# [swarm-kit: shared file, do not fork per repo]  Sourced by docker/swarm.sh. Ported from axi-on-ucie-to-mem.
#
# SWARM_MODEL_PROVIDER (alias: AOU_MODEL_PROVIDER) selects who serves the agents' opus/sonnet/haiku tiers for the
# WHOLE run (Claude Code's provider is process-wide):
#   anthropic (default)  CLAUDE_CODE_OAUTH_TOKEN (subscription, from `claude setup-token`) or ANTHROPIC_API_KEY
#   kimi                 Moonshot's Anthropic-compatible endpoint; needs KIMI_API_KEY.  Tier aliases are remapped so
#                        each agent's `model:` frontmatter keeps working.  COMPLIANCE: sends repo contents to a
#                        China-based provider - never for proprietary / export-sensitive IP.
# Optional tier pins (any provider): ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL; unset = the CLI's defaults.
# Returns non-zero (does not exit) when no usable credential is present.

swarm_resolve_provider() {
  local v
  for v in ANTHROPIC_API_KEY KIMI_API_KEY CLAUDE_CODE_OAUTH_TOKEN; do      # pasted secrets often carry a newline
    if [ -n "${!v:-}" ]; then export "$v=$(printf '%s' "${!v}" | tr -d '[:space:]')"; fi
  done
  case "${ANTHROPIC_API_KEY:-}" in
    sk-ant-oat*)   # a subscription OAuth token stored under the API-key name
      export CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-$ANTHROPIC_API_KEY}"; unset ANTHROPIC_API_KEY
      echo "provider: ANTHROPIC_API_KEY held an OAuth token (sk-ant-oat...) - using it as CLAUDE_CODE_OAUTH_TOKEN" >&2 ;;
  esac
  SWARM_PROVIDER="${SWARM_MODEL_PROVIDER:-${AOU_MODEL_PROVIDER:-anthropic}}"
  case "$SWARM_PROVIDER" in
    anthropic)
      if [ -n "${ANTHROPIC_BASE_URL:-}" ] && [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
        echo "provider: anthropic-compatible endpoint ${ANTHROPIC_BASE_URL}" >&2
      elif [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
        unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
        echo "provider: anthropic (subscription OAuth token)" >&2
      elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        echo "provider: anthropic (Console API key)" >&2
      else
        echo "provider: no credential - set CLAUDE_CODE_OAUTH_TOKEN (claude setup-token) or ANTHROPIC_API_KEY" >&2
        echo "          (or SWARM_MODEL_PROVIDER=kimi with KIMI_API_KEY)" >&2
        return 3
      fi ;;
    kimi)
      if [ -z "${KIMI_API_KEY:-}" ]; then
        echo "provider(kimi): KIMI_API_KEY is not set" >&2; return 3
      fi
      export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL:-https://api.moonshot.ai/anthropic}"
      export ANTHROPIC_AUTH_TOKEN="$KIMI_API_KEY"
      unset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN
      export ANTHROPIC_DEFAULT_OPUS_MODEL="${KIMI_OPUS_MODEL:-kimi-k3}"
      export ANTHROPIC_DEFAULT_SONNET_MODEL="${KIMI_SONNET_MODEL:-kimi-k2.7-code}"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL="${KIMI_HAIKU_MODEL:-kimi-k2.7-code-highspeed}"
      echo "provider: kimi -> ${ANTHROPIC_BASE_URL} (opus=${ANTHROPIC_DEFAULT_OPUS_MODEL} sonnet=${ANTHROPIC_DEFAULT_SONNET_MODEL} haiku=${ANTHROPIC_DEFAULT_HAIKU_MODEL})" >&2
      echo "  COMPLIANCE/IP CAUTION: this run sends repo contents (RTL/DV, diffs, prompts) to Moonshot, a China-based" >&2
      echo "  provider. Do not use it for proprietary or export-sensitive IP; check current export-control status first." >&2 ;;
    *)
      echo "provider: unknown SWARM_MODEL_PROVIDER='$SWARM_PROVIDER' (anthropic | kimi)" >&2; return 2 ;;
  esac
  export SWARM_PROVIDER
}
