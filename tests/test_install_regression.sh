#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="$HOME"
export UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING=1
export UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1
TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/harness-install.XXXXXX")"
ROLLBACK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/harness-rollback.XXXXXX")"
CONFIG_HOME="$(mktemp -d "${TMPDIR:-/tmp}/harness-config.XXXXXX")"
VALIDATION_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/harness-validation.XXXXXX")"
trap 'rm -rf "$TMP_HOME" "$ROLLBACK_HOME" "$VALIDATION_ROOT" "$CONFIG_HOME"' EXIT HUP INT TERM

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

echo "Validation regression: local Serena state must not require manifest entries"
tar -C "$ROOT" --exclude=.git --exclude=.serena -cf - . | tar -C "$VALIDATION_ROOT" -xf -
mkdir -p "$VALIDATION_ROOT/.serena/cache/bash"
printf '%s\n' 'generated cache' > "$VALIDATION_ROOT/.serena/cache/bash/document_symbols.pkl"
printf '%s\n' 'generated project state' > "$VALIDATION_ROOT/.serena/project.local.yml"
bash "$VALIDATION_ROOT/scripts/validate_harness.sh"

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
cat > "$TMP_HOME/expected-config.toml" <<'EOF'
[features.context_management]
experimental_mode = true
EOF
cmp "$TMP_HOME/expected-config.toml" "$TMP_HOME/.codex/config.toml"
# A valid ownership record permits pruning only the obsolete kit entry.
printf '%s\n' obsolete-kit >> "$TMP_HOME/.universal-research-agent-kit/manifests/codex-skills"
cksum "$TMP_HOME/.universal-research-agent-kit/manifests/codex-skills" | awk '{ print $1 ":" $2 }' > "$TMP_HOME/.universal-research-agent-kit/manifests/codex-skills.cksum"
mkdir -p "$TMP_HOME/.agents/skills/obsolete-kit"
printf '%s\n' obsolete > "$TMP_HOME/.agents/skills/obsolete-kit/SKILL.md"
echo "Install regression run 2 (repeat install)"
HOME="$TMP_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/install.sh"

[ ! -e "$TMP_HOME/.agents/skills/obsolete-kit" ]
cmp "$TMP_HOME/expected-config.toml" "$TMP_HOME/.codex/config.toml"

echo "Codex context management config merge regression"
mkdir -p "$CONFIG_HOME/.codex"
for mode in false true missing; do
  {
    printf '%s\n' 'model = "custom-model"' '[features]' 'shell_tool = false' '' '[features.context_management]'
    [ "$mode" = missing ] || printf 'experimental_mode = %s # keep this comment\n' "$mode"
    printf '%s\n' '[mcp_servers.local]' 'command = "custom-command"'
  } > "$CONFIG_HOME/.codex/config.toml"
  if [ "$mode" = missing ]; then
    sed '/^\[mcp_servers.local\]/i\
experimental_mode = true
' "$CONFIG_HOME/.codex/config.toml" > "$CONFIG_HOME/expected.toml"
  else
    sed 's/experimental_mode = false/experimental_mode = true/' "$CONFIG_HOME/.codex/config.toml" > "$CONFIG_HOME/expected.toml"
  fi
  HOME="$CONFIG_HOME" bash "$ROOT/install.sh"
  cmp "$CONFIG_HOME/expected.toml" "$CONFIG_HOME/.codex/config.toml"
done

printf '%s\n' '[agents]' 'max_threads = 9' > "$CONFIG_HOME/.codex/config.toml"
cat > "$CONFIG_HOME/expected.toml" <<'EOF'
[agents]
max_threads = 9

[features.context_management]
experimental_mode = true
EOF
HOME="$CONFIG_HOME" bash "$ROOT/install.sh"
cmp "$CONFIG_HOME/expected.toml" "$CONFIG_HOME/.codex/config.toml"

for unsupported in \
  'features.context_management.experimental_mode = false' \
  'features = { context_management = { experimental_mode = false } }' \
  '[features]
context_management = { experimental_mode = false }' \
  '[features.context_management]
experimental_mode = "false"' \
  '[features."context_management"]
experimental_mode = false' \
  '["fea\u0074ures".context_management]
experimental_mode = false' \
  '[features.context_management]
"experimental_\u006dode" = false' \
  '"fea\u0074ures".context_management.experimental_mode = false' \
  '[features.context_management]
values = [
[1, 2]
]
experimental_mode = false' \
  'instructions = """
[features.context_management]
experimental_mode = false
"""'; do
  printf '%s\n' "$unsupported" > "$CONFIG_HOME/.codex/config.toml"
  cp "$CONFIG_HOME/.codex/config.toml" "$CONFIG_HOME/expected.toml"
  if HOME="$CONFIG_HOME" bash "$ROOT/install.sh" > "$CONFIG_HOME/unsupported.log" 2>&1; then
    echo "Unsupported config unexpectedly accepted: $unsupported" >&2
    exit 1
  fi
  grep -Fq 'Cannot safely update' "$CONFIG_HOME/unsupported.log"
  cmp "$CONFIG_HOME/expected.toml" "$CONFIG_HOME/.codex/config.toml"
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

state_file="$TMP_HOME/.universal-research-agent-kit/integrations.state"
grep -Fqx 'requested_profile=ponytail' "$state_file" || {
  echo "integrations state did not record requested profile" >&2
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
snapshot_home() {
  (cd "$TMP_HOME" && find . -type f -exec cksum {} \; | sort)
}
verify_before="$(snapshot_home)"
HOME="$TMP_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/install.sh" --verify
[ "$verify_before" = "$(snapshot_home)" ] || { echo "verification changed HOME" >&2; exit 1; }
# Verification must reject a drifted required feature without repairing it.
sed 's/experimental_mode = true/experimental_mode = false/' "$TMP_HOME/.codex/config.toml" > "$TMP_HOME/drift.toml"
cp "$TMP_HOME/drift.toml" "$TMP_HOME/.codex/config.toml"
if HOME="$TMP_HOME" bash "$ROOT/install.sh" --verify > "$TMP_HOME/verify-drift.log" 2>&1; then
  echo "verification accepted disabled context management" >&2; exit 1
fi
cmp "$TMP_HOME/drift.toml" "$TMP_HOME/.codex/config.toml"
cp "$TMP_HOME/expected-config.toml" "$TMP_HOME/.codex/config.toml"

state="$TMP_HOME/.universal-research-agent-kit"
mkdir "$state/.lock"
if HOME="$TMP_HOME" sh "$ROOT/install.sh" --cleanup-backups > "$TMP_HOME/cleanup-lock.log" 2>&1; then
  echo "cleanup ignored an active install lock" >&2; exit 1
fi
[ -d "$state/backups" ]
rmdir "$state/.lock"
HOME="$TMP_HOME" sh "$ROOT/install.sh" --cleanup-backups
[ ! -e "$state/backups" ]
[ -f "$state/manifests/codex-skills" ]
grep -Fqx 'third-party-codex-skill' "$TMP_HOME/.agents/skills/third-party/SKILL.md"


echo "Unit regression: kit_restore_entry must not delete a target without its backup"
(
  set -euo pipefail
  source "$ROOT/install.sh"
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
HOME="$BACKUP_FAIL_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/install.sh" >/dev/null 2>&1
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
HOME="$MARKER_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/install.sh" >/dev/null 2>&1
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
HOME="$ROLLBACK_HOME" UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 bash "$ROOT/install.sh" >/dev/null 2>&1
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
