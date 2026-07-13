#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/../lib/install_common.sh"
kit_init_state
kit_enable_rollback

kit_require_real_dir "$HOME/.claude"
kit_require_real_dir "$HOME/.claude/agents"
kit_require_real_dir "$HOME/.claude/skills"

kit_backup_path "$HOME/.claude/CLAUDE.md" "claude/CLAUDE.md"
kit_backup_path "$HOME/.claude/agents" "claude/agents"
kit_backup_path "$HOME/.claude/skills" "claude/skills"

agent_manifest="$KIT_BACKUP_DIR/claude-agents.current"
skill_manifest="$KIT_BACKUP_DIR/claude-skills.current"
kit_create_empty_file "$agent_manifest"
kit_create_empty_file "$skill_manifest"

agent_count=0
for source in "$ROOT/agents"/*.md; do
  [ -f "$source" ] || continue
  name="${source##*/}"
  printf '%s\n' "$name" >> "$agent_manifest"
  agent_count=$((agent_count + 1))
done
[ "$agent_count" -gt 0 ] || kit_die "No Claude agent files found in $ROOT/agents"

skill_count=0
for source in "$ROOT/skills"/*; do
  [ -d "$source" ] || continue
  name="${source##*/}"
  printf '%s\n' "$name" >> "$skill_manifest"
  skill_count=$((skill_count + 1))
done
[ "$skill_count" -gt 0 ] || kit_die "No Claude skill directories found in $ROOT/skills"

sort -o "$agent_manifest" "$agent_manifest"
sort -o "$skill_manifest" "$skill_manifest"
kit_prune_manifest "$HOME/.claude/agents" "$KIT_MANIFEST_ROOT/claude-agents" "$agent_manifest"
kit_prune_manifest "$HOME/.claude/skills" "$KIT_MANIFEST_ROOT/claude-skills" "$skill_manifest"

kit_replace_file "$ROOT/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
for source in "$ROOT/agents"/*.md; do
  [ -f "$source" ] || continue
  kit_replace_file "$source" "$HOME/.claude/agents/${source##*/}"
done
for source in "$ROOT/skills"/*; do
  [ -d "$source" ] || continue
  kit_replace_dir "$source" "$HOME/.claude/skills/${source##*/}"
done

kit_commit_manifest "$agent_manifest" "$KIT_MANIFEST_ROOT/claude-agents"
kit_commit_manifest "$skill_manifest" "$KIT_MANIFEST_ROOT/claude-skills"

echo "Installed Claude Code global protocol to ~/.claude"
