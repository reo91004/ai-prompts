#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[1/4] Installing Claude Code global research protocol..."
bash "$ROOT/claude-code/install.sh"

echo "[2/4] Installing Codex global research protocol..."
bash "$ROOT/codex/install.sh"

echo "[3/4] Installing global gitignore block..."
mkdir -p "$HOME/.config/git"
GLOBAL_IGNORE="$HOME/.config/git/ignore"
touch "$GLOBAL_IGNORE"
if ! grep -q "BEGIN UNIVERSAL RESEARCH AGENT KIT" "$GLOBAL_IGNORE"; then
  cat "$ROOT/global_research_agents.gitignore" >> "$GLOBAL_IGNORE"
  echo "Appended research agent ignore rules to $GLOBAL_IGNORE"
else
  echo "Research agent ignore block already exists in $GLOBAL_IGNORE"
fi

echo "[4/4] Verifying install..."
bash "$ROOT/verify_install.sh"

echo "Done. Restart Claude Code and Codex sessions to ensure all global instructions, agents, and skills are discovered."
