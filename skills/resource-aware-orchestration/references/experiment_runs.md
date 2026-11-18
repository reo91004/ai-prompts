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

For all platforms, wait through the existing waiter instead of polling run state from the model.

### Codex

Start `wait_run.sh` once in a persistent background terminal. When the shell tool yields a `session_id`, continue waiting on that same session with empty input (for example, `write_stdin`) in the current turn until the waiter exits. A tool wait returning early is a reason to keep waiting on the same session. Start a replacement waiter only if the original session is gone and the run still needs waiting.

Keep the turn active through the run's actual exit. Do not poll logs, PIDs, or task lists, send periodic status messages, or end the turn with an interim final. If the user asks a question while waiting, answer briefly and resume waiting on the same session. Apply the completion check below once the waiter exits.

## Resume in a new session

Read the `Running` list in `.plans/HANDOVER.md`. For each run, call `wait_run.sh` as above: it reports an already finished run at once and otherwise waits for it. Never relaunch a run that is still alive.

## After the run

Check the experiment's recorded `exit_code`, the log tail, and the expected artifacts once the run ends. Use the experiment exit code reported by the waiter to judge process success, then confirm the artifacts. Record the outcome in the card or `attempts.json`, move the entry out of `Running`, and on failure diagnose, fix, and launch the next attempt in a new `a<N+1>` directory. Delete the bulky outputs of failed attempts once recorded.

Stop a run only for user cancellation, an explicit deadline, an unrecoverable error, confirmed sustained no-progress, or a resource or equipment emergency: send `kill -TERM <pid>` first and keep checkpoints. A wait that timed out is not a reason to stop.

The parent owns the handover entry when delegating to Codex `experiment_monitor`. The monitor follows the same launch and wait procedure and returns the terminal evidence to the parent.
