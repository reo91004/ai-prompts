# Completion-Driven Long Work


Parent agents must not repeatedly poll long training, synthesis, hardware capture, PIDs, logs, task lists, or mailboxes. Keep routine progress in durable logs and checkpoints; emit a model-visible event only for completion, failure, a permission request, confirmed sustained no-progress, a resource or equipment emergency, or required operator intervention. After an event, the parent verifies exit status and expected artifacts before continuing dependent work.

Run a long command in the foreground and block on it in one tool call — the whole run then costs a single turn. Background it only when there is declared independent work to do meanwhile, and block with one OS-level wait on the process (`wait "$pid"`, or `tail --pid="$pid" -f /dev/null`); a `sleep`/`tail`/status loop is the polling this rule forbids, whatever interval it uses. When a tool wait returns on timeout it carries no information: re-issue the wait and emit nothing. Repeated waits are free only when they are silent, so a per-minute status line is a defect, not progress reporting.

For a fully specified long-running experiment, training, synthesis, or hardware-capture command in Codex, use the pinned `experiment_monitor` through `scripts/run_codex_agent.sh`. This role is `gpt-6-astra` at low effort with `danger-full-access`; it may execute the declared command, block, and collect terminal evidence, but it must not design the experiment, construct a missing command, interpret results, accept claims, or choose an undeclared retry. Do not replace it with an unpinned native child merely to obtain device access. Use a domain specialist before launch when those judgment-bearing tasks remain.

In Claude Code, prefer `Monitor` with a watcher that emits only terminal events. Explicitly request a background subagent when parallel work is useful, but rely on its completion notification only when the running version documents reliable completion semantics. If `Monitor` is unavailable, use a foreground blocking subagent or report the limitation rather than creating an LLM polling loop.

In Codex, direct background terminals require a later session wait or `write_stdin` to surface completion. The parent may continue independent work, then block on the isolated runner session at the dependency boundary. The `experiment_monitor` uses a shell-native blocking wait or the longest policy-allowed tool wait and returns only after a terminal event. A runner-session wait timeout causes another wait without re-analysis and is not failure. Scheduled polling is opt-in only when the user accepts cadence-based checks or the original session cannot remain alive.

## Run scope and cancellation

Before launch, bind the exact command, expected artifacts, progress probe, checkpoint/resume procedure, and graceful cancellation/cleanup to the task. The monitor executes that command; it does not design experiments or accept claims. It defaults to no retry unless one exact trigger, command, and attempt limit are declared.

Keep routine progress in logs. Treat work as alive while its process, log, artifact, CPU, or I/O shows progress. Stop only for user cancellation, an explicit deadline, an unrecoverable error, confirmed sustained no-progress, or a resource/equipment emergency. Before stopping, preserve checkpoints and partial evidence and attempt graceful termination; force termination is a last resort. A failed step blocks dependents, not independent valid findings.
