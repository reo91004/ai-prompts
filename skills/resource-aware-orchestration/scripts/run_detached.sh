#!/usr/bin/env bash
# Start a long command outside the agent session so it survives the session ending.
# The run directory receives: command, started_at, pid, log, and exit_code when the command ends.
# From Codex it also records codex_thread and, after exit_code, wakes that session unless its turn
# already read wait_run.sh's report, retrying for about a day (wake.log). RUN_WAKE_THREAD overrides
# the thread to wake; an empty value disables the wake. On macOS the run keeps the machine from idle sleep.
set -euo pipefail
[ "$#" -ge 3 ] && [ "$2" = -- ] || { echo "Usage: run_detached.sh <run-dir> -- <command> [args...]" >&2; exit 2; }
wake_thread="${RUN_WAKE_THREAD-${CODEX_THREAD_ID:-}}"
if [ -n "$wake_thread" ] && [ -n "${CODEX_SANDBOX:-}" ]; then
  echo "The Codex sandbox blocks the completion wake. Rerun this launch outside the sandbox (escalated), or set RUN_WAKE_THREAD= and wait in the turn with wait_run.sh." >&2
  exit 3
fi
mkdir -p "$1"
dir="$(cd "$1" && pwd)"
shift 2
[ ! -e "$dir/pid" ] || { echo "$dir already holds a run; use a new attempt directory." >&2; exit 1; }
printf '%q ' "$@" > "$dir/command"
echo >> "$dir/command"
date -u +%Y-%m-%dT%H:%M:%SZ > "$dir/started_at"
[ -z "$wake_thread" ] || echo "$wake_thread" > "$dir/codex_thread"
wake="$(cd "$(dirname "$0")" && pwd)/wake_codex.py"
# start_new_session detaches from the agent's process group, so closing the session does not signal the run.
python3 - "$dir" "$wake" "$@" <<'PY'
import os, shutil, subprocess, sys
run_dir, wake, command = sys.argv[1], sys.argv[2], sys.argv[3:]
script = ('"$@"; echo $? > "$0/exit_code.tmp"; mv "$0/exit_code.tmp" "$0/exit_code"; '
          '[ ! -s "$0/codex_thread" ] || python3 -I "$RUN_WAKE_SCRIPT" "$0" >> "$0/wake.log" 2>&1')
with open(os.path.join(run_dir, "log"), "ab") as log:
    child = subprocess.Popen(["bash", "-c", script, run_dir, *command], env=dict(os.environ, RUN_WAKE_SCRIPT=wake),
                             stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
with open(os.path.join(run_dir, "pid"), "w") as handle:
    handle.write(f"{child.pid}\n")
if shutil.which("caffeinate"):
    # macOS idle sleep would pause the run and its wake; -w ends the assertion when the wrapper exits.
    subprocess.Popen(["caffeinate", "-i", "-w", str(child.pid)], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
PY
echo "started pid $(cat "$dir/pid"); wait with: $(dirname "$0")/wait_run.sh '$dir'"
