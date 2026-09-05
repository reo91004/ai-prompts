#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/install_common.sh"

usage() {
  echo "usage: install_all.sh [--integrations none|ponytail]"
  echo "  ponytail  core plus pinned Ponytail and Sequential Thinking MCP (default)"
  echo "  none      core plus Graphify/Headroom; reconciles away kit and legacy integrations"
}

INTEGRATIONS_PROFILE=ponytail
while [ "$#" -gt 0 ]; do
  case "$1" in
    --integrations)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      case "$2" in
        none|ponytail) INTEGRATIONS_PROFILE="$2" ;;
        *) usage >&2; exit 2 ;;
      esac
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done
if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" = "1" ]; then
  INTEGRATIONS_PROFILE=none
fi

kit_init_state
kit_enable_rollback

echo "[1/6] Installing Claude Code global research protocol..."
bash "$ROOT/claude-code/install.sh"

echo "[2/6] Installing Codex global research protocol..."
bash "$ROOT/codex/install.sh"

echo "[3/6] Installing global gitignore block..."
GLOBAL_IGNORE="$HOME/.config/git/ignore"
kit_replace_managed_block "$GLOBAL_IGNORE" "$ROOT/global_research_agents.gitignore" "git/ignore" '# BEGIN UNIVERSAL RESEARCH AGENT KIT' '# END UNIVERSAL RESEARCH AGENT KIT'
echo "Installed research agent ignore rules to $GLOBAL_IGNORE"

echo "[4/6] Reconciling integrations (profile: $INTEGRATIONS_PROFILE)..."
if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" = "1" ]; then
  echo "Skipped integration reconciliation by explicit environment setting."
  kit_write_integrations_state "$INTEGRATIONS_PROFILE" "skipped_env" "skipped_env" "skipped_env" "skipped_env" "skipped_env"
else
  bash "$ROOT/install_integrations.sh" "$INTEGRATIONS_PROFILE"
fi

echo "[5/6] Installing Graphify and Headroom tooling..."
if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" = "1" ]; then
  echo "Skipped tooling installation by explicit environment setting."
  kit_write_tooling_state "skipped_env" "skipped_env" "skipped_env" "skipped_env" "-" "-" "$HOME/.universal-research-agent-kit/tooling/bin"
else
  bash "$ROOT/install_tooling.sh"
fi

echo "[6/6] Verifying install..."
bash "$ROOT/verify_install.sh"

echo "Done. Restart Claude Code and Codex sessions to ensure all global instructions, agents, and skills are discovered."
