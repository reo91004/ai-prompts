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

state_file="$TMP_HOME/.universal-research-agent-kit/integrations.state"
grep -Fqx 'requested_profile=none' "$state_file" || {
  echo "integrations state did not record profile none" >&2
  exit 1
}
grep -Fqx 'codex_ponytail=skipped_env' "$state_file" || {
  echo "integrations state did not record the env skip" >&2
  exit 1
}
[ ! -d "$TMP_HOME/.universal-research-agent-kit/.lock" ] || {
  echo "install lock left behind after a successful run" >&2
  exit 1
}

[ -x "$TMP_HOME/.agents/skills/resource-aware-orchestration/scripts/detect_resources.sh" ]
[ -x "$TMP_HOME/.claude/skills/resource-aware-orchestration/scripts/detect_resources.sh" ]
[ -x "$TMP_HOME/.agents/skills/resource-aware-orchestration/scripts/run_codex_agent.sh" ]
[ -x "$TMP_HOME/.claude/skills/resource-aware-orchestration/scripts/run_codex_agent.sh" ]
HOME="$TMP_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/verify_install.sh"

echo "Unit regression: kit_restore_entry must not delete a target without its backup"
(
  set -euo pipefail
  source "$ROOT/lib/install_common.sh"
  unit_dir="$(mktemp -d "${TMPDIR:-/tmp}/restore-unit.XXXXXX")"
  printf 'precious\n' > "$unit_dir/target"
  rc=0
  kit_restore_entry "$unit_dir/target" "$unit_dir/missing-backup" || rc=$?
  [ "$rc" -ne 0 ] || { echo "kit_restore_entry succeeded without a backup" >&2; exit 1; }
  grep -Fqx 'precious' "$unit_dir/target" || { echo "kit_restore_entry destroyed the target" >&2; exit 1; }
  rm -rf "$unit_dir"
)

echo "Backup-failure regression: a failed backup copy must leave the original intact"
# chmod 000 only blocks non-root readers; this scenario requires a non-root run.
BACKUP_FAIL_HOME="$(mktemp -d "${TMPDIR:-/tmp}/harness-backupfail.XXXXXX")"
mkdir -p "$BACKUP_FAIL_HOME/.claude/agents"
printf 'user prompt\n' > "$BACKUP_FAIL_HOME/.claude/CLAUDE.md"
printf 'user agent\n' > "$BACKUP_FAIL_HOME/.claude/agents/user-agent.md"
claude_md_before="$(cksum "$BACKUP_FAIL_HOME/.claude/CLAUDE.md")"
chmod 000 "$BACKUP_FAIL_HOME/.claude/agents"
set +e
HOME="$BACKUP_FAIL_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/install_all.sh" >/dev/null 2>&1
backup_fail_rc=$?
set -e
chmod 700 "$BACKUP_FAIL_HOME/.claude/agents"
[ "$backup_fail_rc" -ne 0 ] || { echo "install unexpectedly succeeded with an unreadable agents dir" >&2; rm -rf "$BACKUP_FAIL_HOME"; exit 1; }
grep -Fqx 'user agent' "$BACKUP_FAIL_HOME/.claude/agents/user-agent.md" || {
  echo "backup failure destroyed the original agents directory" >&2
  rm -rf "$BACKUP_FAIL_HOME"
  exit 1
}
claude_md_after="$(cksum "$BACKUP_FAIL_HOME/.claude/CLAUDE.md")"
[ "$claude_md_before" = "$claude_md_after" ] || {
  echo "backup failure altered the pre-existing CLAUDE.md" >&2
  rm -rf "$BACKUP_FAIL_HOME"
  exit 1
}
[ ! -d "$BACKUP_FAIL_HOME/.universal-research-agent-kit/.lock" ] || {
  echo "install lock left behind after a backup failure" >&2
  rm -rf "$BACKUP_FAIL_HOME"
  exit 1
}
rm -rf "$BACKUP_FAIL_HOME"

echo "Marker regression: a malformed gitignore marker pair must abort without changing the file"
MARKER_HOME="$(mktemp -d "${TMPDIR:-/tmp}/harness-marker.XXXXXX")"
mkdir -p "$MARKER_HOME/.config/git"
printf '%s\n' 'user rule' '# BEGIN UNIVERSAL RESEARCH AGENT KIT' '# BEGIN UNIVERSAL RESEARCH AGENT KIT' 'stale' '# END UNIVERSAL RESEARCH AGENT KIT' > "$MARKER_HOME/.config/git/ignore"
ignore_before="$(cksum "$MARKER_HOME/.config/git/ignore")"
set +e
HOME="$MARKER_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/install_all.sh" >/dev/null 2>&1
marker_rc=$?
set -e
[ "$marker_rc" -ne 0 ] || { echo "install unexpectedly succeeded with malformed markers" >&2; rm -rf "$MARKER_HOME"; exit 1; }
ignore_after="$(cksum "$MARKER_HOME/.config/git/ignore")"
[ "$ignore_before" = "$ignore_after" ] || {
  echo "malformed marker handling modified the user gitignore" >&2
  rm -rf "$MARKER_HOME"
  exit 1
}
rm -rf "$MARKER_HOME"

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
