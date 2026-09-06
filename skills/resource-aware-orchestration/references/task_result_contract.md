# Delegated Task and Result

Give each child the information needed to stay within scope and return usable evidence. A normal tool message is enough; a separate packet document is optional.

| Field | Content |
|---|---|
| objective | One bounded deliverable. |
| agent | Requested role, selected through the runtime; effective settings need runtime evidence. |
| allowed_scope | Files, systems, and actions the child may inspect or change. |
| forbidden_scope | Protected state and exclusions, including no nested delegation. |
| write_permission | Read-only or explicit file ownership; parallel writers use isolated worktrees with a merge plan. |
| acceptance_criteria | Behavior or claim and the evidence that would establish it. |
| return_mode | Concise synthesis or full result as the task requires. |

Return status (`PASS`, `FAIL`, `BLOCKED`, or `RESOURCE_*`), findings, relevant commands and exit codes, inspected/created artifact paths, and remaining concrete risks. Large output belongs in an artifact rather than the parent's context. Do not invent evidence or turn an unavailable/failed step into a pass. Failure blocks dependent work; unrelated analysis can continue.

Read [platform dispatch](platform_dispatch.md) for role/model selection. For concurrent local compute, use the resource gate in [the skill](../SKILL.md); do not run a detector solely to dispatch a remote read-only child.

Long work additionally binds the exact command, expected artifacts, progress probe, checkpoint/resume procedure, and graceful cancellation/cleanup. Use [long-run coordination](long_runs.md); routine progress stays in logs, and elapsed time or a wait timeout alone does not mean failure.
