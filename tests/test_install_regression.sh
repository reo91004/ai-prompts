#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="$HOME"
TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/harness-install.XXXXXX")"
trap 'rm -rf "$TMP_HOME"' EXIT HUP INT TERM

home_prompt_signature() {
  for path in "$REAL_HOME/.codex/AGENTS.md" "$REAL_HOME/.claude/CLAUDE.md"; do
    if [ -f "$path" ]; then
      cksum "$path"
    else
      echo "absent $path"
    fi
  done
}

before_signature="$(home_prompt_signature)"
mkdir -p \
  "$TMP_HOME/.codex/agents" \
  "$TMP_HOME/.agents/skills/third-party" \
  "$TMP_HOME/.claude/agents" \
  "$TMP_HOME/.claude/skills/third-party"
printf '%s\n' 'third-party-codex-agent' > "$TMP_HOME/.codex/agents/third_party.toml"
printf '%s\n' 'third-party-codex-skill' > "$TMP_HOME/.agents/skills/third-party/SKILL.md"
printf '%s\n' 'third-party-claude-agent' > "$TMP_HOME/.claude/agents/third-party.md"
printf '%s\n' 'third-party-claude-skill' > "$TMP_HOME/.claude/skills/third-party/SKILL.md"

for run in 1 2; do
  echo "Install regression run $run"
  HOME="$TMP_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/install_all.sh"
done

grep -Fqx 'third-party-codex-agent' "$TMP_HOME/.codex/agents/third_party.toml"
grep -Fqx 'third-party-codex-skill' "$TMP_HOME/.agents/skills/third-party/SKILL.md"
grep -Fqx 'third-party-claude-agent' "$TMP_HOME/.claude/agents/third-party.md"
grep -Fqx 'third-party-claude-skill' "$TMP_HOME/.claude/skills/third-party/SKILL.md"

for manifest in claude-agents claude-skills codex-agents codex-skills; do
  path="$TMP_HOME/.universal-research-agent-kit/manifests/$manifest"
  [ -f "$path" ] && [ -f "$path.cksum" ]
  expected="$(cat "$path.cksum")"
  actual="$(cksum "$path" | awk '{ print $1 ":" $2 }')"
  [ "$expected" = "$actual" ] || { echo "invalid manifest checksum: $manifest" >&2; exit 1; }
done

[ -x "$TMP_HOME/.agents/skills/resource-aware-orchestration/scripts/detect_resources.sh" ]
[ -x "$TMP_HOME/.claude/skills/resource-aware-orchestration/scripts/detect_resources.sh" ]
HOME="$TMP_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/verify_install.sh"

after_signature="$(home_prompt_signature)"
[ "$before_signature" = "$after_signature" ] || {
  echo "real HOME prompt files changed during isolated install test" >&2
  exit 1
}
[ "$HOME" = "$REAL_HOME" ]

echo "Install regression tests passed."
