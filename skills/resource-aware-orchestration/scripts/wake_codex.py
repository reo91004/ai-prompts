#!/usr/bin/env python3
"""Wake the Codex session in <run-dir>/codex_thread after a run ends and confirm the woken turn finished.

run_detached.sh starts this once exit_code exists and appends its output to <run-dir>/wake.log.
The session normally holds its turn on wait_run.sh, so the wake is a backup: after a grace period
it exits without a message when that session's rollout already holds wait_run.sh's report.
Each attempt queues a message carrying a unique token with `codex queue --resume`, then reads the
thread's rollout until the turn holding that token completes. A failed resume, a turn that ended
with an error (expired login, network, proxy), or a message never picked up is retried with
backoff for about a day, so an unattended run does not stay unanalyzed. A queued message stays
queued until a turn takes it, so a retry adds a second copy; when an open TUI holds the thread
("active writer"), that TUI delivers the message after its current turn, and the wake waits for it
instead of queueing copies. Repeated copies flood the session with identical turns, which has sent
the model into an endless "stop" loop.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import time

GRACE = int(os.environ.get("RUN_WAKE_GRACE", "60"))  # lets a turn polling wait_run.sh read the end first
RETRY_DELAYS = [GRACE, 60, 300, 900, 1800] + [3600] * 20
PICKUP_LIMIT = 1800  # seconds a queued message may wait before it is sent again
WRITER_PICKUP_LIMIT = 24 * 3600  # an open TUI delivers after its current turn, however long that runs
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


def seen(thread, run_dir, exit_code):
    """True when the session already read wait_run.sh's report of this run's end."""
    path = rollout(thread)
    return bool(path) and f"run ended: exit_code={exit_code} dir={run_dir}" in path.read_text()


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


def wait_for_turn(thread, token, sleep=time.sleep, clock=time.monotonic, pickup_limit=PICKUP_LIMIT):
    start, started = clock(), None
    while True:
        path = rollout(thread)
        state = turn_state(path, token) if path else "queued"
        if state in ("done", "error", "aborted"):
            return state
        if state == "running" and started is None:
            started = clock()
        if started is None and clock() - start > pickup_limit:
            return "not picked up"
        if started is not None and clock() - started > TURN_LIMIT:
            return "unfinished"
        sleep(POLL)


def wake(run_dir, sleep=time.sleep, clock=time.monotonic):
    thread = (run_dir / "codex_thread").read_text().strip()
    exit_code = (run_dir / "exit_code").read_text().strip()
    for attempt, delay in enumerate(RETRY_DELAYS, 1):
        sleep(delay)
        if seen(thread, run_dir, exit_code):
            log(f"attempt {attempt}: the session already read the run's end from wait_run.sh; no wake sent")
            return 0
        token = f"wake-{attempt}-{time.time_ns()}"
        message = (f"Run finished: exit_code={exit_code} dir={run_dir} [{token}]. Apply 'After the run' in the "
                   "resource-aware-orchestration skill's references/experiment_runs.md to this run, then continue "
                   "the planned work. If this run's outcome is already recorded, reply 'already handled' and end the turn.")
        if codex("app-server", "daemon", "version")[0] != 0:
            log("daemon start: " + codex("app-server", "daemon", "start")[1][-300:])
        status, output = codex("queue", "--thread", thread, "--message", message, "--resume")
        log(f"attempt {attempt}: {output}")
        writer = "active writer" in output
        if status != 0 or ("could not resume" in output and not writer):
            continue
        state = wait_for_turn(thread, token, sleep, clock, WRITER_PICKUP_LIMIT if writer else PICKUP_LIMIT)
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
