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
[ ! -e "$T/a1/codex_thread" ] && [ ! -e "$T/a1/wake.log" ]

# A Codex-launched run wakes its thread after exit_code exists and confirms the woken turn in the rollout.
# The fake codex plays the daemon: a queued message becomes a completed turn in $HOME/.codex/sessions.
mkdir -p "$T/bin" "$T/home/.codex/sessions"
cat > "$T/bin/codex" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_CODEX_CALLS"
[ "$1 $2 $3" != "app-server daemon version" ] || exit "$FAKE_DAEMON_STATUS"
if [ "$1" = queue ]; then
  printf '{"payload":{"type":"user_message","message":"%s"}}\n{"payload":{"type":"task_complete","error":null}}\n' \
    "$(printf '%s' "$5" | grep -o '\[wake-[0-9-]*\]')" >> "$HOME/.codex/sessions/rollout-x-$3.jsonl"
  echo "Queued message m for thread $3."
fi
EOF
chmod +x "$T/bin/codex"
export FAKE_CODEX_CALLS="$T/calls" FAKE_DAEMON_STATUS=1 RUN_WAKE_GRACE=0
wait_wake() { for _ in $(seq 100); do grep -q 'woken turn' "$1/wake.log" 2>/dev/null && return; sleep 0.1; done; return 1; }
HOME="$T/home" PATH="$T/bin:$PATH" CODEX_THREAD_ID=thread-1 "$S/run_detached.sh" "$T/a3" -- bash -c 'exit 4' >/dev/null
"$S/wait_run.sh" "$T/a3" >/dev/null
wait_wake "$T/a3"
grep -qx thread-1 "$T/a3/codex_thread"
grep -qx 'app-server daemon start' "$T/calls"
grep -q "^queue --thread thread-1 --message Run finished: exit_code=4 dir=$T/a3 \[wake-1-[0-9]*\]\. .* --resume$" "$T/calls"
grep -q 'attempt 1: woken turn done' "$T/a3/wake.log"

: > "$T/calls"; FAKE_DAEMON_STATUS=0
HOME="$T/home" PATH="$T/bin:$PATH" CODEX_THREAD_ID=thread-1 RUN_WAKE_THREAD=parent-2 "$S/run_detached.sh" "$T/a4" -- true >/dev/null
HOME="$T/home" PATH="$T/bin:$PATH" CODEX_THREAD_ID=thread-1 RUN_WAKE_THREAD= "$S/run_detached.sh" "$T/a5" -- true >/dev/null
"$S/wait_run.sh" "$T/a4" >/dev/null; "$S/wait_run.sh" "$T/a5" >/dev/null
wait_wake "$T/a4"; sleep 0.5
[ "$(grep -c '^queue ' "$T/calls")" = 1 ] && grep -q '^queue --thread parent-2 ' "$T/calls"
! grep -q 'daemon start' "$T/calls"
[ ! -e "$T/a5/codex_thread" ] && [ ! -e "$T/a5/wake.log" ]

# Inside the Codex sandbox the wake cannot reach the daemon, so a waking launch is refused before it starts.
if CODEX_SANDBOX=seatbelt CODEX_THREAD_ID=thread-1 "$S/run_detached.sh" "$T/a6" -- true 2>/dev/null; then
  echo "sandboxed launch with a wake was accepted" >&2; exit 1
fi
[ ! -e "$T/a6" ]
CODEX_SANDBOX=seatbelt CODEX_THREAD_ID=thread-1 RUN_WAKE_THREAD= "$S/run_detached.sh" "$T/a7" -- true >/dev/null
"$S/wait_run.sh" "$T/a7" >/dev/null
echo "detached run test passed"
