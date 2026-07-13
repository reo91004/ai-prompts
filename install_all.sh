#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/install_common.sh"

usage() {
  echo "usage: install_all.sh [--integrations none|ponytail|ultra]"
  echo "  none      core prompts, agents, and skills only (default)"
  echo "  ponytail  core plus the pinned Ponytail plugin"
  echo "  ultra     core plus Ponytail and the pinned LazyCodex workflow"
}

INTEGRATIONS_PROFILE=none
while [ "$#" -gt 0 ]; do
  case "$1" in
    --integrations)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      case "$2" in
        none|ponytail|ultra) INTEGRATIONS_PROFILE="$2" ;;
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

replace_managed_block() {
  local target="$1"
  local block="$2"
  local tmp
  local begin_count
  local end_count
  local begin_line
  local end_line

  kit_require_real_dir "$(dirname "$target")"
  [ ! -L "$target" ] || kit_die "Refusing to replace a symlinked gitignore file: $target"
  if [ -e "$target" ] && [ ! -f "$target" ]; then
    kit_die "Global gitignore path is not a regular file: $target"
  fi
  if [ ! -e "$target" ]; then
    printf '' > "$target"
  fi

  begin_count="$(grep -c '# BEGIN UNIVERSAL RESEARCH AGENT KIT' "$target" || true)"
  end_count="$(grep -c '# END UNIVERSAL RESEARCH AGENT KIT' "$target" || true)"
  if [ "$begin_count" -ne 0 ] || [ "$end_count" -ne 0 ]; then
    if [ "$begin_count" -ne 1 ] || [ "$end_count" -ne 1 ]; then
      kit_die "Malformed kit marker pair in $target (begin=$begin_count end=$end_count); repair the markers before reinstalling."
    fi
    begin_line="$(grep -n '# BEGIN UNIVERSAL RESEARCH AGENT KIT' "$target" | cut -d: -f1)"
    end_line="$(grep -n '# END UNIVERSAL RESEARCH AGENT KIT' "$target" | cut -d: -f1)"
    if [ "$begin_line" -ge "$end_line" ]; then
      kit_die "Kit end marker precedes the begin marker in $target; repair the markers before reinstalling."
    fi
  fi

  kit_backup_path "$target" "git/ignore"
  tmp="$(mktemp "$target.tmp.XXXXXX")"

  if [ "$begin_count" -eq 1 ]; then
    awk -v block_file="$block" '
      BEGIN {
        while ((getline line < block_file) > 0) {
          managed = managed line ORS
        }
      }
      /# BEGIN UNIVERSAL RESEARCH AGENT KIT/ {
        printf "%s", managed
        in_block = 1
        next
      }
      /# END UNIVERSAL RESEARCH AGENT KIT/ {
        in_block = 0
        next
      }
      !in_block { print }
    ' "$target" > "$tmp"
  else
    cat "$target" > "$tmp"
    if [ -s "$target" ]; then
      printf "\n" >> "$tmp"
    fi
    cat "$block" >> "$tmp"
  fi

  mv "$tmp" "$target"
}

record_integrations_profile() {
  local profile_file="$KIT_STATE_ROOT/integrations.profile"
  local tmp

  kit_require_regular_or_absent "$profile_file"
  kit_backup_path "$profile_file" "state/integrations.profile"
  tmp="$(mktemp "$profile_file.tmp.XXXXXX")"
  printf '%s\n' "$INTEGRATIONS_PROFILE" > "$tmp"
  mv "$tmp" "$profile_file"
}

echo "[1/5] Installing Claude Code global research protocol..."
bash "$ROOT/claude-code/install.sh"

echo "[2/5] Installing Codex global research protocol..."
bash "$ROOT/codex/install.sh"

echo "[3/5] Installing global gitignore block..."
GLOBAL_IGNORE="$HOME/.config/git/ignore"
replace_managed_block "$GLOBAL_IGNORE" "$ROOT/global_research_agents.gitignore"
echo "Installed research agent ignore rules to $GLOBAL_IGNORE"

echo "[4/5] Installing opt-in integrations (profile: $INTEGRATIONS_PROFILE)..."
if [ "$INTEGRATIONS_PROFILE" = "none" ]; then
  echo "Skipped external integrations; pass --integrations ponytail or --integrations ultra to opt in."
else
  bash "$ROOT/install_integrations.sh" "$INTEGRATIONS_PROFILE"
fi
record_integrations_profile

echo "[5/5] Verifying install..."
bash "$ROOT/verify_install.sh"

echo "Done. Restart Claude Code and Codex sessions to ensure all global instructions, agents, and skills are discovered."
