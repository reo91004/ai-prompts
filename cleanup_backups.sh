#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash cleanup_backups.sh

Deletes installation snapshots under:
  ~/.universal-research-agent-kit/backups

Ownership manifests and active configurations are preserved.
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

case "${HOME:-}" in
  ""|/) echo "Refusing to clean backups with an unsafe HOME." >&2; exit 1 ;;
  /*) ;;
  *) echo "HOME must be an absolute directory: $HOME" >&2; exit 1 ;;
esac

STATE_ROOT="$HOME/.universal-research-agent-kit"
BACKUP_ROOT="$STATE_ROOT/backups"

if [ -L "$STATE_ROOT" ] || [ -L "$BACKUP_ROOT" ]; then
  echo "Refusing to clean a symlinked kit state path." >&2
  exit 1
fi

if [ ! -d "$BACKUP_ROOT" ]; then
  echo "No kit backup snapshots found."
  exit 0
fi

rm -rf -- "$BACKUP_ROOT"
echo "Kit backup snapshots deleted."
