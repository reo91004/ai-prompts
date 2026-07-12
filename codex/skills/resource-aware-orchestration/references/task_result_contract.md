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

The detector snapshot in `resource_budget` must include normalized `platform=macos|linux|wsl`, `captured_epoch`, `snapshot_age_seconds`, `writer_slots=1`, and `heavy_command_slots=1`. Linux/WSL evidence also records cgroup v2 discovery state and the resolved process cgroup path when available. Snapshots older than 600 seconds are stale and cannot authorize a spawn wave. Structured detection failures and stale snapshots return concurrency one with process exit 3; callers must preserve that degraded state rather than treating the safe numeric value as a successful detection.

## Result

Every child result must contain:

- `status`: `PASS`, `FAIL`, `BLOCKED`, or a specific `RESOURCE_*` status;
- `evidence`: artifact-specific observations supporting the status;
- `commands`: commands with exit codes, including failed and unavailable checks;
- `artifacts`: created or inspected artifact paths;
- `deviations`: any difference from the task packet;
- `remaining_risks`: unresolved risks and dependent work that remains blocked.

A result is incomplete if a required field is absent. A resource or tool failure must remain visible and cannot be converted to `PASS` by omission or reviewer judgment.
