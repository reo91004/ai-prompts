#!/usr/bin/env bash
# Block until a run started by run_detached.sh ends, then print its outcome; returns at once if it already ended.
# Works from any session: it only reads the run directory.
set -euo pipefail
[ "$#" -eq 1 ] || { echo "Usage: wait_run.sh <run-dir>" >&2; exit 2; }
dir="$(cd "$1" && pwd)"  # absolute, so wake_codex.py can find this report in the session rollout
pid="$(cat "$dir/pid")"
# shortcut: a PID reused after a host restart keeps this waiting; check started_at if a wait seems endless.
while [ ! -e "$dir/exit_code" ] && kill -0 "$pid" 2>/dev/null; do sleep 10; done
if [ -e "$dir/exit_code" ]; then
  echo "run ended: exit_code=$(cat "$dir/exit_code") dir=$dir"
else
  echo "run ended without exit_code (killed or host restarted): dir=$dir"
  exit 1
fi
