#!/usr/bin/env bash
set -euo pipefail
if [ -n "${CRUCIBLE_ROOT:-}" ]; then
  exec "$CRUCIBLE_ROOT/bin/crucible" "$@"
fi
if command -v crucible >/dev/null 2>&1; then
  exec crucible "$@"
fi
engine="$HOME/reo/crucible/bin/crucible"
if [ ! -x "$engine" ]; then
  printf '%s\n' 'Crucible is unavailable. Set CRUCIBLE_ROOT to its checkout or install its CLI.' >&2
  exit 127
fi
exec "$engine" "$@"
