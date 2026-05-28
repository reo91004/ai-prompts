#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$HOME/.claude/agents" "$HOME/.claude/skills"

backup_file() {
  local dst="$1"
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.bak.$TS"
    echo "Backed up $dst -> $dst.bak.$TS"
  fi
}

backup_file "$HOME/.claude/CLAUDE.md"
cp "$ROOT/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
cp "$ROOT/agents"/*.md "$HOME/.claude/agents/"
cp -R "$ROOT/skills"/* "$HOME/.claude/skills/"

echo "Installed Claude Code global protocol to ~/.claude"
