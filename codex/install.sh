#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$HOME/.codex/agents" "$HOME/.agents/skills"

backup_file() {
  local dst="$1"
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.bak.$TS"
    echo "Backed up $dst -> $dst.bak.$TS"
  fi
}

backup_file "$HOME/.codex/AGENTS.md"
cp "$ROOT/AGENTS.md" "$HOME/.codex/AGENTS.md"
cp "$ROOT/agents"/*.toml "$HOME/.codex/agents/"
cp -R "$ROOT/skills"/* "$HOME/.agents/skills/"

echo "Installed Codex global protocol to ~/.codex and ~/.agents/skills"
