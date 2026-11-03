#!/usr/bin/env bash
set -euo pipefail
if [ -d "$HOME/.universal-research-agent-kit/.lock" ]; then
  printf '%s\n' 'The kit installer is running; start Crucible after it finishes.' >&2
  exit 1
fi
if [ -n "${CRUCIBLE_ROOT:-}" ]; then
  exec "$CRUCIBLE_ROOT/bin/crucible" "$@"
fi
if command -v crucible >/dev/null 2>&1; then
  exec crucible "$@"
fi
python="$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python"
if [ ! -x "$python" ]; then python="$(command -v python3)"; fi
exec "$python" "$(dirname "${BASH_SOURCE[0]}")/engine.py" run "$@"
