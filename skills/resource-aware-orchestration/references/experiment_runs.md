# Running Experiments

Every experiment, training, synthesis, or hardware capture runs independently of the agent session that started it. Closing Codex, Claude Code, or OpenCode, or starting a new session, leaves the run going and its outcome readable.

## Launch

Start every experiment command with the project's detached runner or this skill's `scripts/run_detached.sh`, using the attempt directory from the project layout as the run directory. In Codex, also detach research commands expected to take at least one minute, including preparation and analysis commands.

```bash
<skill-dir>/scripts/run_detached.sh private_work/experiments/<date>-<id>-<topic>/a<N> -- python experiments/explore/x.py --config configs/x.json
```

The script detaches the command into its own session and writes `command`, `started_at`, `pid`, `log`, and, when the command ends, `exit_code` into the run directory. Before launching, add the run directory, exact wait command, linked card when applicable, and next action to `Running` in `.plans/HANDOVER.md`.

## Wait

`scripts/wait_run.sh <run-dir>` blocks until the run ends and prints its exit code. It returns immediately when the run already ended, and exits 1 when the process vanished without an exit code (killed or host restarted). It reads only the run directory, so any session can call it.

- In Claude Code, start `wait_run.sh` with `Monitor`. Its single output line is the completion event. Continue independent work meanwhile.
- In OpenCode, run `wait_run.sh` with native `shell` and `background: true, monitor: true` where event delivery works. Otherwise, use a blocking shell call.

On every platform, wait through the waiter or, in Codex, the wake instead of polling run state from the model.

### Codex

Codex waits inside the turn. After launching, record the run in `Running`, start `wait_run.sh <run-dir>` once in a background terminal, finish independent work, then keep polling that same terminal session with empty input and `yield_time_ms` 300000 until it prints the run's end. A poll that returns without output means the run is still going; poll the same session again. Do not end the turn to wait, start a second waiter, or poll logs or PIDs from the model. With several runs, wait on the one expected to end first; a `wait_run.sh` on a run that already ended returns at once.

Under an active goal, ending the turn starts an automatic continuation turn, so a session that ends its turn to wait spins through empty turns and drifts toward closing the goal. Polling a live `wait_run.sh` session is a verified wait, which is progress for the goal's no-progress check. A running experiment is never a reason to mark the goal `blocked` or `complete`; leave it active and keep waiting.

The wake is the backup for a turn that ends anyway: an interruption, an expired login, a crash, or a closed session. `run_detached.sh` records the launching session's `CODEX_THREAD_ID` in `codex_thread`. One minute after the run ends, `wake_codex.py` reads that session's rollout; if `wait_run.sh`'s report is already there, it exits without a message. Otherwise it queues one `Run finished: exit_code=<N> dir=<run-dir> [<token>]` message with `codex queue --resume`, starting the managed app-server daemon first if it is absent, and reads the rollout until the turn holding its token completes. An open TUI that holds the session (`already has an active writer`) delivers the message after its current turn, so the wake waits for that instead of sending copies. A failed resume or a turn that ended in an error is sent again after 1, 5, 15, and 30 minutes and then hourly for about a day; every attempt is logged in `wake.log`. Each copy becomes one more identical turn, and hundreds of them once pushed the model into an endless "stop" loop, so the wake sends a copy only when the previous one cannot arrive. On macOS the run also holds an idle-sleep assertion until the wake finishes; a closed laptop lid still sleeps.

When a completion message arrives, apply the completion check below and continue toward the goal, launching the next attempt the same way; if the outcome is already recorded, reply that it is handled and end the turn.

A sandboxed command cannot reach the daemon, so `run_detached.sh` refuses a waking launch inside the Codex sandbox (exit 3). Rerun the launch outside the sandbox with escalated permissions, or launch with `RUN_WAKE_THREAD=` and rely on the in-turn wait alone. Set `RUN_WAKE_THREAD=<thread>` to wake a different session. A woken turn runs under the session's own approval policy, so unattended work needs a policy that does not stop for approval.

## Resume in a new session

Read the `Running` list in `.plans/HANDOVER.md`. For each run, call `wait_run.sh` as above: it reports an already finished run at once and otherwise waits for it. In Codex, for a run still going, write this session's `CODEX_THREAD_ID` into its `codex_thread` so a backup wake reaches this session, then wait in the turn as above. Never relaunch a run that is still alive.

## After the run

Check the experiment's recorded `exit_code`, the log tail, and the expected artifacts once the run ends. Use the experiment exit code reported by the waiter or wake message to judge process success, then confirm the artifacts. Record the outcome in the card or `attempts.json`, move the entry out of `Running`, and on failure diagnose, fix, and launch the next attempt in a new `a<N+1>` directory. Delete the bulky outputs of failed attempts once recorded.

Stop a run only for user cancellation, an explicit deadline, an unrecoverable error, confirmed sustained no-progress, or a resource or equipment emergency: send `kill -TERM <pid>` first and keep checkpoints. A wait that timed out is not a reason to stop.

The parent owns the handover entry when delegating to Codex `experiment_monitor`. The monitor follows the same launch and wait procedure and returns the terminal evidence to the parent.
