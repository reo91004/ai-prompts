#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$HOME/.claude"

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
    "$HOME/.claude/agents"|"$HOME/.claude/skills") ;;
    *)
      echo "Refusing to reset unmanaged directory: $dst" >&2
      exit 1
      ;;
  esac

  backup_dir "$dst"
  rm -rf "$dst"
  mkdir -p "$dst"
}

backup_file "$HOME/.claude/CLAUDE.md"
reset_managed_dir "$HOME/.claude/agents"
reset_managed_dir "$HOME/.claude/skills"

cp "$ROOT/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
cp "$ROOT/agents"/*.md "$HOME/.claude/agents/"
cp -R "$ROOT/skills"/* "$HOME/.claude/skills/"

echo "Installed Claude Code global protocol to ~/.claude"
