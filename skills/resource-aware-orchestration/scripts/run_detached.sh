#!/usr/bin/env bash
# Start a long command outside the agent session so it survives the session ending.
# The run directory receives: command, started_at, pid, log, and exit_code when the command ends.
set -euo pipefail
[ "$#" -ge 3 ] && [ "$2" = -- ] || { echo "Usage: run_detached.sh <run-dir> -- <command> [args...]" >&2; exit 2; }
mkdir -p "$1"
dir="$(cd "$1" && pwd)"
shift 2
[ ! -e "$dir/pid" ] || { echo "$dir already holds a run; use a new attempt directory." >&2; exit 1; }
printf '%q ' "$@" > "$dir/command"
echo >> "$dir/command"
date -u +%Y-%m-%dT%H:%M:%SZ > "$dir/started_at"
# start_new_session detaches from the agent's process group, so closing the session does not signal the run.
python3 - "$dir" "$@" <<'PY'
import os, subprocess, sys
run_dir, command = sys.argv[1], sys.argv[2:]
with open(os.path.join(run_dir, "log"), "ab") as log:
    child = subprocess.Popen(["bash", "-c", '"$@"; echo $? > "$0/exit_code.tmp"; mv "$0/exit_code.tmp" "$0/exit_code"', run_dir, *command],
                             stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
with open(os.path.join(run_dir, "pid"), "w") as handle:
    handle.write(f"{child.pid}\n")
PY
echo "started pid $(cat "$dir/pid"); wait with: $(dirname "$0")/wait_run.sh '$dir'"
