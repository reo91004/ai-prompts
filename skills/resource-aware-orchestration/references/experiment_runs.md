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

Codex waits by being woken, not by holding the turn. `run_detached.sh` records the launching session's `CODEX_THREAD_ID` in `codex_thread`. When the run ends, `wake_codex.py` queues a `Run finished: exit_code=<N> dir=<run-dir> [<token>]` message to that session with `codex queue --resume`, starting the managed app-server daemon first if it is absent. The daemon runs that turn whether or not a TUI is open; an open TUI shows it, and a busy turn receives it when it ends. The wake then reads the session's rollout until the turn holding its token completes. A failed resume, a turn that ended in an error (expired login, network, proxy), or a message not picked up within 30 minutes is sent again after 1, 5, 15, and 30 minutes and then hourly for about a day; every attempt is logged in `wake.log`. On macOS the run also holds an idle-sleep assertion until the wake finishes; a closed laptop lid still sleeps.

After launching, confirm `codex_thread` exists in the run directory, record the run in `Running`, finish independent work, and end the turn with one line naming the run directory. Do not hold the turn with a waiter, poll logs or PIDs, or send periodic status messages. When a completion message arrives, apply the completion check below and continue toward the goal, launching the next attempt the same way; if the outcome is already recorded, reply that it is handled and end the turn.

A sandboxed command cannot reach the daemon, so `run_detached.sh` refuses a waking launch inside the Codex sandbox (exit 3). Rerun the launch outside the sandbox with escalated permissions. If escalation is not available, launch with `RUN_WAKE_THREAD=` and hold the turn instead: start `wait_run.sh` once in a background terminal and keep waiting on that same session with empty input until it exits. Set `RUN_WAKE_THREAD=<thread>` to wake a different session. A woken turn runs under the session's own approval policy, so unattended work needs a policy that does not stop for approval.

## Resume in a new session

Read the `Running` list in `.plans/HANDOVER.md`. For each run, call `wait_run.sh` as above: it reports an already finished run at once and otherwise waits for it. In Codex, for a run still going, write this session's `CODEX_THREAD_ID` into its `codex_thread` so the wake reaches this session, then end the turn as above. Never relaunch a run that is still alive.

## After the run

Check the experiment's recorded `exit_code`, the log tail, and the expected artifacts once the run ends. Use the experiment exit code reported by the waiter or wake message to judge process success, then confirm the artifacts. Record the outcome in the card or `attempts.json`, move the entry out of `Running`, and on failure diagnose, fix, and launch the next attempt in a new `a<N+1>` directory. Delete the bulky outputs of failed attempts once recorded.

Stop a run only for user cancellation, an explicit deadline, an unrecoverable error, confirmed sustained no-progress, or a resource or equipment emergency: send `kill -TERM <pid>` first and keep checkpoints. A wait that timed out is not a reason to stop.

The parent owns the handover entry when delegating to Codex `experiment_monitor`. The monitor follows the same launch and wait procedure and returns the terminal evidence to the parent.
