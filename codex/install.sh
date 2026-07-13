#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/../lib/install_common.sh"
kit_init_state
kit_enable_rollback

kit_require_real_dir "$HOME/.codex"
kit_require_real_dir "$HOME/.agents"
kit_require_real_dir "$HOME/.codex/agents"
kit_require_real_dir "$HOME/.agents/skills"

kit_backup_path "$HOME/.codex/AGENTS.md" "codex/AGENTS.md"
kit_backup_path "$HOME/.codex/agents" "codex/agents"
kit_backup_path "$HOME/.agents/skills" "shared/skills"

agent_manifest="$KIT_BACKUP_DIR/codex-agents.current"
skill_manifest="$KIT_BACKUP_DIR/codex-skills.current"
kit_create_empty_file "$agent_manifest"
kit_create_empty_file "$skill_manifest"

agent_count=0
for source in "$ROOT/agents"/*.toml; do
  [ -f "$source" ] || continue
  name="${source##*/}"
  printf '%s\n' "$name" >> "$agent_manifest"
  agent_count=$((agent_count + 1))
done
[ "$agent_count" -gt 0 ] || kit_die "No Codex agent files found in $ROOT/agents"

skill_count=0
for source in "$ROOT/skills"/*; do
  [ -d "$source" ] || continue
  name="${source##*/}"
  printf '%s\n' "$name" >> "$skill_manifest"
  skill_count=$((skill_count + 1))
done
[ "$skill_count" -gt 0 ] || kit_die "No Codex skill directories found in $ROOT/skills"

sort -o "$agent_manifest" "$agent_manifest"
sort -o "$skill_manifest" "$skill_manifest"
kit_prune_manifest "$HOME/.codex/agents" "$KIT_MANIFEST_ROOT/codex-agents" "$agent_manifest"
kit_prune_manifest "$HOME/.agents/skills" "$KIT_MANIFEST_ROOT/codex-skills" "$skill_manifest"

kit_replace_file "$ROOT/AGENTS.md" "$HOME/.codex/AGENTS.md"
for source in "$ROOT/agents"/*.toml; do
  [ -f "$source" ] || continue
  kit_replace_file "$source" "$HOME/.codex/agents/${source##*/}"
done
for source in "$ROOT/skills"/*; do
  [ -d "$source" ] || continue
  kit_replace_dir "$source" "$HOME/.agents/skills/${source##*/}"
done

kit_commit_manifest "$agent_manifest" "$KIT_MANIFEST_ROOT/codex-agents"
kit_commit_manifest "$skill_manifest" "$KIT_MANIFEST_ROOT/codex-skills"

echo "Installed Codex global protocol to ~/.codex and ~/.agents/skills"
