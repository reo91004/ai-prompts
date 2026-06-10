#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d_%H%M%S)"

backup_file() {
  local dst="$1"
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.bak.$TS"
    echo "Backed up $dst -> $dst.bak.$TS"
  fi
}

replace_managed_block() {
  local target="$1"
  local block="$2"
  local tmp

  mkdir -p "$(dirname "$target")"
  touch "$target"
  backup_file "$target"
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

echo "[1/4] Installing Claude Code global research protocol..."
bash "$ROOT/claude-code/install.sh"

echo "[2/4] Installing Codex global research protocol..."
bash "$ROOT/codex/install.sh"

echo "[3/4] Installing global gitignore block..."
GLOBAL_IGNORE="$HOME/.config/git/ignore"
replace_managed_block "$GLOBAL_IGNORE" "$ROOT/global_research_agents.gitignore"
echo "Installed research agent ignore rules to $GLOBAL_IGNORE"

echo "[4/4] Verifying install..."
bash "$ROOT/verify_install.sh"

echo "Done. Restart Claude Code and Codex sessions to ensure all global instructions, agents, and skills are discovered."
