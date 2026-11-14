# Running Experiments

Every experiment, training, synthesis, or hardware capture runs independently of the agent session that started it. Closing Codex, Claude Code, or OpenCode, or starting a new session, leaves the run going and its outcome readable.

## Launch

Start every experiment command, however short it looks, with this skill's `scripts/run_detached.sh`, using the attempt directory from the project layout as the run directory:

```bash
<skill-dir>/scripts/run_detached.sh private_work/experiments/<date>-<id>-<topic>/a<N> -- python experiments/explore/x.py --config configs/x.json
```

The script detaches the command into its own session and writes `command`, `started_at`, `pid`, `log`, and, when the command ends, `exit_code` into the run directory. Before launching, add the run to the `Running` list in `.plans/HANDOVER.md`: run directory, card, what the run answers, and what to do when it ends.

## Wait

`scripts/wait_run.sh <run-dir>` blocks until the run ends and prints its exit code. It returns immediately when the run already ended, and exits 1 when the process vanished without an exit code (killed or host restarted). It reads only the run directory, so any session can call it.

- Claude Code: start `wait_run.sh` with `Monitor`; its single output line is the completion event. Continue independent work meanwhile.
- Codex: run `wait_run.sh` in one blocking shell call with the longest allowed timeout. If the tool call times out, issue the same call again without comment; the run is unaffected.
- OpenCode: run `wait_run.sh` with native `shell` and `background: true, monitor: true` where event delivery works; otherwise block on it in one call as in Codex.

Do not poll logs, PIDs, or task lists from the model; one waiting call per dependency boundary is enough.

## Resume in a new session

Read the `Running` list in `.plans/HANDOVER.md`. For each run, call `wait_run.sh` as above: it reports an already finished run at once and otherwise waits for it. Never relaunch a run that is still alive.

## After the run

Read `exit_code`, the log tail, and the expected artifacts; a zero exit code alone is not success. Record the outcome in the card or `attempts.json`, move the entry out of `Running`, and on failure diagnose, fix, and launch the next attempt in a new `a<N+1>` directory. Delete the bulky outputs of failed attempts once recorded.

Stop a run only for user cancellation, an explicit deadline, an unrecoverable error, confirmed sustained no-progress, or a resource or equipment emergency: send `kill -TERM <pid>` first and keep checkpoints. A wait that timed out is not a reason to stop.

The Codex `experiment_monitor` role follows the same launch and wait procedure when a parent hands it a fully specified command; it does not design, interpret, or retry.
