#!/usr/bin/env bash
set -euo pipefail

# Deletes only the backups this kit's installer creates (*.bak.* under managed paths).
usage() {
  cat <<'USAGE'
Usage: bash cleanup_backups.sh

Deletes backups created by this kit:
  ~/.claude/CLAUDE.md.bak.*  ~/.claude/agents.bak.*  ~/.claude/skills.bak.*
  ~/.codex/AGENTS.md.bak.*   ~/.codex/agents.bak.*   ~/.agents/skills.bak.*
  ~/.config/git/ignore.bak.*
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

# The globs below are the whitelist: rm can only match these managed backup paths.
shopt -s nullglob
backups=(
  "$HOME"/.claude/CLAUDE.md.bak.*
  "$HOME"/.claude/agents.bak.*
  "$HOME"/.claude/skills.bak.*
  "$HOME"/.codex/AGENTS.md.bak.*
  "$HOME"/.codex/agents.bak.*
  "$HOME"/.agents/skills.bak.*
  "$HOME"/.config/git/ignore.bak.*
)
shopt -u nullglob

if [ "${#backups[@]}" -eq 0 ]; then
  echo "No managed backups found."
  exit 0
fi

for path in "${backups[@]}"; do
  echo "Removing $path"
  rm -rf -- "$path"
done
echo "Managed backups deleted."
