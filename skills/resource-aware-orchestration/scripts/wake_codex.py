#!/usr/bin/env python3
"""Wake the Codex session in <run-dir>/codex_thread after a run ends and confirm the woken turn finished.

run_detached.sh starts this once exit_code exists and appends its output to <run-dir>/wake.log.
Each attempt queues a message carrying a unique token with `codex queue --resume`, then reads the
thread's rollout until the turn holding that token completes. A failed resume, a turn that ended
with an error (expired login, network, proxy), or a message never picked up is retried with
backoff for about a day, so an unattended run does not stay unanalyzed. Duplicate messages are
harmless: each tells the session to stop if the outcome is already recorded.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import time

RETRY_DELAYS = [0, 60, 300, 900, 1800] + [3600] * 20
PICKUP_LIMIT = 1800  # seconds a queued message may wait before it is sent again
TURN_LIMIT = 6 * 3600  # seconds a started turn may run before the wake is sent again
POLL = 30


def log(text):
    print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), text.strip(), flush=True)


def codex(*args):
    # The daemon must not inherit the launching tool call's thread identity.
    env = {key: value for key, value in os.environ.items() if key != "CODEX_THREAD_ID"}
    result = subprocess.run(["codex", *args], capture_output=True, text=True, env=env)
    return result.returncode, result.stdout + result.stderr


def rollout(thread):
    matches = sorted((Path.home() / ".codex/sessions").rglob(f"rollout-*-{thread}.jsonl"))
    return matches[-1] if matches else None


def turn_state(path, token):
    """Return queued, running, done, error, or aborted for the turn whose input holds token."""
    seen = False
    with path.open() as handle:
        for line in handle:
            if not seen:
                seen = token in line
                continue
            payload = json.loads(line).get("payload")
            kind = payload.get("type") if isinstance(payload, dict) else None
            if kind == "task_complete":
                return "error" if payload.get("error") else "done"
            if kind == "turn_aborted":
                return "aborted"
    return "running" if seen else "queued"


def wait_for_turn(thread, token, sleep=time.sleep, clock=time.monotonic):
    start, started = clock(), None
    while True:
        path = rollout(thread)
        state = turn_state(path, token) if path else "queued"
        if state in ("done", "error", "aborted"):
            return state
        if state == "running" and started is None:
            started = clock()
        if started is None and clock() - start > PICKUP_LIMIT:
            return "not picked up"
        if started is not None and clock() - started > TURN_LIMIT:
            return "unfinished"
        sleep(POLL)


def wake(run_dir, sleep=time.sleep, clock=time.monotonic):
    thread = (run_dir / "codex_thread").read_text().strip()
    exit_code = (run_dir / "exit_code").read_text().strip()
    for attempt, delay in enumerate(RETRY_DELAYS, 1):
        sleep(delay)
        token = f"wake-{attempt}-{time.time_ns()}"
        message = (f"Run finished: exit_code={exit_code} dir={run_dir} [{token}]. Apply 'After the run' in the "
                   "resource-aware-orchestration skill's references/experiment_runs.md to this run, then continue "
                   "the planned work. If this run's outcome is already recorded, reply 'already handled' and end the turn.")
        if codex("app-server", "daemon", "version")[0] != 0:
            log("daemon start: " + codex("app-server", "daemon", "start")[1][-300:])
        status, output = codex("queue", "--thread", thread, "--message", message, "--resume")
        log(f"attempt {attempt}: {output}")
        if status != 0 or "could not resume" in output:
            continue
        state = wait_for_turn(thread, token, sleep, clock)
        log(f"attempt {attempt}: woken turn {state}")
        if state == "done":
            return 0
        if state == "aborted":
            # Only a person interrupts a turn; they are present and decide what happens next.
            return 0
    log("gave up; queued messages run when the session is next opened")
    return 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: wake_codex.py <run-dir>")
    sys.exit(wake(Path(sys.argv[1]).absolute()))
