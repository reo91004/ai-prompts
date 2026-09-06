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

# Keep the user config intact except for this feature; unsupported TOML forms
# fail before replacement instead of risking a duplicate or misplaced key.
config="$HOME/.codex/config.toml"
kit_require_regular_or_absent "$config"
config_input="$config"
[ -f "$config_input" ] || config_input=/dev/null
config_next="$KIT_BACKUP_DIR/codex-config.next"
if ! awk '
  function finish_section() {
    if (target && !key_seen) print "experimental_mode = true"
  }
  {
    line = $0
    # Multiline strings can contain text that looks like table headers.
    if (index(line, "\"\"\"") || index(line, sprintf("%c%c%c", 39, 39, 39))) exit 1
    sub(/#.*/, "", line)
    gsub(/[[:space:]]/, "", line)
    normalized = line
    gsub(/[\"\047]/, "", normalized)
    if (target && line ~ /=\[/ && line !~ /]$/) exit 1
    if (line ~ /^\[/) {
      if (index(line, "\\")) exit 1
      finish_section()
      target = (line == "[features.context_management]")
      if ((normalized ~ /^\[features(\.|])/ && normalized != line) ||
          normalized ~ /^\[\[features(\.|])/ ||
          normalized ~ /^\[features\.context_management\.experimental_mode(\.|])/) exit 1
      if (target) {
        if (section_seen++) exit 1
        key_seen = 0
      }
      section = line
    } else if ((section == "" || section == "[features]" || target) &&
               line ~ /^[^=]*\\/) {
      exit 1
    } else if (target && line ~ /^experimental_mode=/) {
      if (key_seen++ || line !~ /^experimental_mode=(true|false)$/) exit 1
      sub(/=[[:space:]]*(true|false)/, "= true")
    } else if ((section == "" && normalized ~ /^features[.=]/) ||
               (section == "[features]" && normalized ~ /^context_management[.=]/) ||
               (target && (normalized ~ /^experimental_mode\./ ||
                           (normalized ~ /^experimental_mode=/ && normalized != line)))) {
      exit 1
    }
    print
  }
  END {
    finish_section()
    if (!section_seen) {
      if (NR) print ""
      print "[features.context_management]\nexperimental_mode = true"
    }
  }
' "$config_input" > "$config_next"; then
  kit_die "Cannot safely update $config. Use [features.context_management] with a boolean experimental_mode; quoted/dotted/inline feature settings and multiline values in this table are unsupported; multiline strings and escaped table headers or related keys are unsupported."
fi
kit_backup_path "$config" "codex/config.toml"
kit_replace_file "$config_next" "$config"

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
