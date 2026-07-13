#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="$HOME"
TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/harness-install.XXXXXX")"
ROLLBACK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/harness-rollback.XXXXXX")"
trap 'rm -rf "$TMP_HOME" "$ROLLBACK_HOME"' EXIT HUP INT TERM

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

echo "Install regression run 1 (POSIX sh bootstrap)"
HOME="$TMP_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 sh "$ROOT/install.sh"
echo "Install regression run 2 (repeat install)"
HOME="$TMP_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/install_all.sh"

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

grep -Fqx 'none' "$TMP_HOME/.universal-research-agent-kit/integrations.profile" || {
  echo "integrations profile was not recorded as none" >&2
  exit 1
}
[ ! -d "$TMP_HOME/.universal-research-agent-kit/.lock" ] || {
  echo "install lock left behind after a successful run" >&2
  exit 1
}

[ -x "$TMP_HOME/.agents/skills/resource-aware-orchestration/scripts/detect_resources.sh" ]
[ -x "$TMP_HOME/.claude/skills/resource-aware-orchestration/scripts/detect_resources.sh" ]
HOME="$TMP_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/verify_install.sh"

echo "Rollback regression: fail the gitignore phase and expect full restore"
mkdir -p "$ROLLBACK_HOME/.claude/skills/third-party" "$ROLLBACK_HOME/.config/git/ignore"
printf '%s\n' 'third-party-claude-skill' > "$ROLLBACK_HOME/.claude/skills/third-party/SKILL.md"
set +e
HOME="$ROLLBACK_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/install_all.sh" >/dev/null 2>&1
rollback_rc=$?
set -e
[ "$rollback_rc" -ne 0 ] || { echo "install unexpectedly succeeded with a broken gitignore target" >&2; exit 1; }
[ ! -f "$ROLLBACK_HOME/.claude/CLAUDE.md" ] || { echo "rollback left an installed CLAUDE.md behind" >&2; exit 1; }
[ ! -f "$ROLLBACK_HOME/.codex/AGENTS.md" ] || { echo "rollback left an installed AGENTS.md behind" >&2; exit 1; }
if find "$ROLLBACK_HOME/.claude/agents" -mindepth 1 2>/dev/null | grep -q .; then
  echo "rollback left installed Claude agents behind" >&2
  exit 1
fi
grep -Fqx 'third-party-claude-skill' "$ROLLBACK_HOME/.claude/skills/third-party/SKILL.md" || {
  echo "rollback damaged a third-party skill" >&2
  exit 1
}
[ ! -d "$ROLLBACK_HOME/.universal-research-agent-kit/.lock" ] || {
  echo "install lock left behind after a rolled-back run" >&2
  exit 1
}
ls "$ROLLBACK_HOME/.universal-research-agent-kit/backups/"run.*/journal.tsv.rolled-back >/dev/null 2>&1 || {
  echo "rollback journal record is missing" >&2
  exit 1
}

after_signature="$(home_prompt_signature)"
[ "$before_signature" = "$after_signature" ] || {
  echo "real HOME prompt files changed during isolated install test" >&2
  exit 1
}
[ "$HOME" = "$REAL_HOME" ]

echo "Install regression tests passed."
