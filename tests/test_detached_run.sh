#!/usr/bin/env bash
# A detached run survives in its own session, records its exit code, and can be awaited from any shell.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/resource-aware-orchestration/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

"$S/run_detached.sh" "$T/a1" -- bash -c 'echo hello; sleep 2; exit 3' >/dev/null
pid="$(cat "$T/a1/pid")"
[ "$(ps -o pgid= -p "$pid" | tr -d ' ')" != "$(ps -o pgid= -p $$ | tr -d ' ')" ]
out="$("$S/wait_run.sh" "$T/a1")"
[ "$out" = "run ended: exit_code=3 dir=$T/a1" ]
grep -qx hello "$T/a1/log"
[ -s "$T/a1/started_at" ] && grep -q '^bash -c ' "$T/a1/command"

if "$S/run_detached.sh" "$T/a1" -- true 2>/dev/null; then echo "reused a run directory" >&2; exit 1; fi

"$S/run_detached.sh" "$T/a2" -- sleep 60 >/dev/null
kill -9 "$(cat "$T/a2/pid")"
if "$S/wait_run.sh" "$T/a2" >/dev/null; then echo "killed run reported success" >&2; exit 1; fi
echo "detached run test passed"
