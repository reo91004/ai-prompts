#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/install_common.sh"
kit_init_state

replace_managed_block() {
  local target="$1"
  local block="$2"
  local tmp

  kit_require_real_dir "$(dirname "$target")"
  [ ! -L "$target" ] || kit_die "Refusing to replace a symlinked gitignore file: $target"
  if [ -e "$target" ] && [ ! -f "$target" ]; then
    kit_die "Global gitignore path is not a regular file: $target"
  fi
  if [ ! -e "$target" ]; then
    printf '' > "$target"
  fi
  kit_backup_path "$target" "git/ignore"
  tmp="$(mktemp "$target.tmp.XXXXXX")"

  if grep -q "BEGIN UNIVERSAL RESEARCH AGENT KIT" "$target"; then
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

echo "[1/5] Installing Claude Code global research protocol..."
bash "$ROOT/claude-code/install.sh"

echo "[2/5] Installing Codex global research protocol..."
bash "$ROOT/codex/install.sh"

echo "[3/5] Installing global gitignore block..."
GLOBAL_IGNORE="$HOME/.config/git/ignore"
replace_managed_block "$GLOBAL_IGNORE" "$ROOT/global_research_agents.gitignore"
echo "Installed research agent ignore rules to $GLOBAL_IGNORE"

echo "[4/5] Installing supported integrations..."
if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" = "1" ]; then
  echo "Skipped external integrations by explicit environment setting."
else
  bash "$ROOT/install_integrations.sh"
fi

echo "[5/5] Verifying install..."
bash "$ROOT/verify_install.sh"

echo "Done. Restart Claude Code and Codex sessions to ensure all global instructions, agents, and skills are discovered."
