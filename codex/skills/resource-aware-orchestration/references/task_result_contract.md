# Delegated Task And Result Contract

## Task Packet

Every delegated task must contain:

- `objective`: one bounded deliverable;
- `allowed_scope`: files, systems, data, and actions the child may inspect or change;
- `forbidden_scope`: explicit exclusions and protected state;
- `write_permission`: `read-only` or the exact writable paths;
- `acceptance_criteria`: observable conditions and required deterministic evidence;
- `resource_budget`: detector snapshot, concurrency, writer/heavy-command slots, and task cap;
- `review_budget`: necessity decision, reviewer count, allowed rounds, and delta scope;
- `stop_condition`: completion, failure, resource, and escalation conditions;
- `output_schema`: the result fields below.

Two children may not own the same deliverable. A child must stop before acting outside its packet.

The detector snapshot in `resource_budget` must include normalized `platform=macos|linux|wsl`, `captured_epoch`, `snapshot_age_seconds`, `agent_slots`, `writer_slots=1`, and `heavy_command_slots`. Linux/WSL evidence also records cgroup v2 discovery state and the resolved process cgroup path when available. Snapshots older than 600 seconds are stale and cannot authorize a spawn wave. `RESOURCE_UNKNOWN` and `RESOURCE_STALE` exit 3 and must stay visible as degraded detection states; they are not evidence of resource shortage and must not be converted to a successful detection.

## Long-Running Work Declaration

Any child command expected to run long (training, synthesis, capture, large trace preprocessing, large test suites) must declare before launch:

- `command`: the exact long-running command;
- `expected_artifacts`: paths the command should produce or extend;
- `progress_probe`: how liveness is observed (log tail, artifact growth, CPU/I/O, heartbeat);
- `checkpoint_path`: where resumable state is written, or `none` with justification;
- `resume_command`: how to continue from the checkpoint;
- `graceful_cancel`: the tool-native or signal-based cancellation procedure;
- `cleanup_command`: how to release resources and temporary state;
- `resource_class`: `cpu_heavy`, `io_heavy`, `gpu`, or `instrument`;
- `claim_bearing`: whether the output feeds a research claim.

Elapsed time or a mailbox wait timeout alone never fails or cancels a declared long-running command. Cancel only for user request, an explicit deadline in the packet, an unrecoverable error, confirmed no-progress across repeated probes, or a resource or equipment emergency — and checkpoint, preserve logs and partial artifacts, and attempt graceful termination first.

## Result

Every child result must contain:

- `status`: `PASS`, `FAIL`, `BLOCKED`, or a specific `RESOURCE_*` status;
- `evidence`: artifact-specific observations supporting the status;
- `commands`: commands with exit codes, including failed and unavailable checks;
- `artifacts`: created or inspected artifact paths;
- `deviations`: any difference from the task packet;
- `remaining_risks`: unresolved risks and dependent work that remains blocked.

A result is incomplete if a required field is absent. A resource or tool failure must remain visible and cannot be converted to `PASS` by omission or reviewer judgment.
