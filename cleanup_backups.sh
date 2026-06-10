#!/usr/bin/env bash
set -euo pipefail

delete=0

usage() {
  cat <<'USAGE'
Usage:
  bash cleanup_backups.sh          # dry-run; print managed backups
  bash cleanup_backups.sh --delete # delete managed backups

Only backups created by this kit are targeted:
  ~/.claude/CLAUDE.md.bak.*
  ~/.claude/agents.bak.*
  ~/.claude/skills.bak.*
  ~/.codex/AGENTS.md.bak.*
  ~/.codex/agents.bak.*
  ~/.agents/skills.bak.*
  ~/.config/git/ignore.bak.*
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --delete)
      delete=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

is_managed_backup() {
  local path="$1"
  case "$path" in
    "$HOME"/.claude/CLAUDE.md.bak.*|\
    "$HOME"/.claude/agents.bak.*|\
    "$HOME"/.claude/skills.bak.*|\
    "$HOME"/.codex/AGENTS.md.bak.*|\
    "$HOME"/.codex/agents.bak.*|\
    "$HOME"/.agents/skills.bak.*|\
    "$HOME"/.config/git/ignore.bak.*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

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

if [ "$delete" -eq 0 ]; then
  echo "Dry run. Managed backups that would be deleted:"
else
  echo "Deleting managed backups:"
fi

for path in "${backups[@]}"; do
  if ! is_managed_backup "$path"; then
    echo "Refusing unmanaged path: $path" >&2
    exit 1
  fi

  echo "  $path"
  if [ "$delete" -eq 1 ]; then
    rm -rf -- "$path"
  fi
done

if [ "$delete" -eq 0 ]; then
  echo "Run with --delete to remove these backups."
else
  echo "Managed backups deleted."
fi
