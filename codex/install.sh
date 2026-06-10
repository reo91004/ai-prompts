#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$HOME/.codex" "$HOME/.agents"

backup_file() {
  local dst="$1"
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.bak.$TS"
    echo "Backed up $dst -> $dst.bak.$TS"
  fi
}

backup_dir() {
  local dst="$1"
  if [ -d "$dst" ]; then
    cp -R "$dst" "$dst.bak.$TS"
    echo "Backed up $dst -> $dst.bak.$TS"
  fi
}

reset_managed_dir() {
  local dst="$1"
  case "$dst" in
    "$HOME/.codex/agents"|"$HOME/.agents/skills") ;;
    *)
      echo "Refusing to reset unmanaged directory: $dst" >&2
      exit 1
      ;;
  esac

  backup_dir "$dst"
  rm -rf "$dst"
  mkdir -p "$dst"
}

backup_file "$HOME/.codex/AGENTS.md"
reset_managed_dir "$HOME/.codex/agents"
reset_managed_dir "$HOME/.agents/skills"

cp "$ROOT/AGENTS.md" "$HOME/.codex/AGENTS.md"
cp "$ROOT/agents"/*.toml "$HOME/.codex/agents/"
cp -R "$ROOT/skills"/* "$HOME/.agents/skills/"

echo "Installed Codex global protocol to ~/.codex and ~/.agents/skills"
