# Delegated Task And Result Contract

## Task Packet

Every delegated task must contain:

- `objective`: one bounded deliverable;
- `requested_agent`: the exact role name, or `main` when no child is used;
- `declared_model` and `declared_reasoning_effort`: values read from the selected agent definition, not inferred from its description;
- `spawn_transport`: `native_agent_tool` or `isolated_codex_cli`; native Codex delegation also records `fork_mode`, and Claude delegation records any model or effort environment overrides;
- `allowed_scope`: files, systems, data, and actions the child may inspect or change;
- `forbidden_scope`: explicit exclusions and protected state;
- `write_permission`: `read-only`, the exact writable paths, or `danger-full-access` only for the pinned `experiment_monitor` with an explicit command and permission justification;
- `acceptance_criteria`: observable conditions and required deterministic evidence;
- `resource_budget`: detector snapshot, concurrency, writer/heavy-command slots, and task cap;
- `review_budget`: necessity decision, reviewer count, allowed rounds, and delta scope;
- `stop_condition`: completion, failure, resource, and escalation conditions;
- `return_mode`: `concise_summary` or `full_result`;
- `summary_budget`: the maximum summary size the parent expects;
- `output_schema`: the result fields below.

Two children may not own the same deliverable. A child must stop before acting outside its packet.

High-volume work (large test suites, log mining, wide greps, document retrieval, large diffs) defaults to `return_mode: concise_summary`: the child writes raw output to an artifact and returns only the synthesis, so delegation actually isolates context instead of relaying thousands of lines back into the parent.

The detector snapshot in `resource_budget` must include normalized `platform=macos|linux|wsl`, `captured_epoch`, `snapshot_age_seconds`, `agent_slots`, `writer_slots=1`, `heavy_command_slots`, and `spawn_authorized`. Linux/WSL evidence also records cgroup v2 discovery state and the resolved process cgroup path when available. Snapshots older than 600 seconds are stale: they report `spawn_authorized=0` with zero agent slots and cannot authorize a spawn wave. `RESOURCE_UNKNOWN` reports `spawn_authorized=read_only` at the configured ceiling. Both exit 3 and must stay visible as degraded detection states; they are not evidence of resource shortage and must not be converted to a successful detection.

## Long-Running Work Declaration

Any child command expected to run long (training, synthesis, capture, large trace preprocessing, large test suites) must declare before launch:

- `command`: the exact long-running command;
- `expected_artifacts`: paths the command should produce or extend;
- `progress_probe`: how liveness is observed (log tail, artifact growth, CPU/I/O, heartbeat);
- `completion_transport`: `claude_monitor`, `claude_subagent_notification`, `codex_isolated_runner_session`, `codex_agent_mailbox`, or `foreground_blocking_wait`;
- `parent_resume_condition`: the terminal event and result fields that unblock dependent parent work;
- `event_emission`: which completion, failure, permission, sustained-no-progress, resource or equipment emergency, or operator-intervention events may enter model context; routine progress remains in artifacts;
- `wait_budget`: the longest policy-allowed blocking wait and the no-analysis re-wait behavior after a timeout;
- `retry_policy`: `none` by default for `experiment_monitor`, or one exact pre-authorized retry command, trigger, and attempt limit;
- `checkpoint_path`: where resumable state is written, or `none` with justification;
- `resume_command`: how to continue from the checkpoint;
- `graceful_cancel`: the tool-native or signal-based cancellation procedure;
- `cleanup_command`: how to release resources and temporary state;
- `resource_class`: `cpu_heavy`, `io_heavy`, `gpu`, or `instrument`;
- `claim_bearing`: whether the output feeds a research claim.

The long-running result also records `completion_event`: observed transport, timestamp, exit status, and terminal condition.

Elapsed time or a completion-transport wait timeout alone never fails or cancels a declared long-running command. `codex_agent_mailbox` applies only to native non-monitor children; `experiment_monitor` uses `codex_isolated_runner_session`. Cancel only for user request, an explicit deadline in the packet, an unrecoverable error, confirmed no-progress across repeated probes, or a resource or equipment emergency — and checkpoint, preserve logs and partial artifacts, and attempt graceful termination first.

## Result

Every child result must contain:

- `status`: `PASS`, `FAIL`, `BLOCKED`, or a specific `RESOURCE_*` status;
- `dispatch_provenance`: requested agent, declared model, effort, and sandbox mode, requested approval policy, spawn transport, fork mode or environment overrides;
- `effective_agent`, `effective_model`, and `effective_reasoning_effort`: runtime-observed values, or the literal `unverified` when the runtime does not expose them; declarations are not runtime evidence;
- `evidence`: artifact-specific observations supporting the status;
- `commands`: commands with exit codes, including failed and unavailable checks;
- `artifacts`: created or inspected artifact paths;
- `evidence_pointers`: artifact paths, file ranges, commands, and exit codes the parent can inspect instead of re-reading raw output;
- `raw_output_artifact`: where large raw output was stored, when `return_mode` is `concise_summary`;
- `parent_action`: the exact decision or next step the parent can take from this result;
- `deviations`: any difference from the task packet;
- `remaining_risks`: unresolved risks and dependent work that remains blocked.

A result is incomplete if a required field is absent. A resource or tool failure must remain visible and cannot be converted to `PASS` by omission or reviewer judgment.
