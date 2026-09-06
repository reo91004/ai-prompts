---
name: resource-aware-orchestration
description: Use to coordinate independent agent deliverables, concurrent local compute, or long-running jobs.
---

# Bounded Delegation

Delegate for a concrete independent deliverable, a large read that benefits from a summary, or required specialist judgment. Keep small or tightly coupled work local. Children do not delegate; agent slots are a ceiling, not a target.

Give each child its objective, allowed/forbidden scope, ownership, and acceptance evidence. Use [the task/result contract](references/task_result_contract.md) when preparing a dispatch. Large outputs stay in artifacts; collect the synthesis, relevant commands/exits, evidence paths, and remaining risks. Continue independent work while a child runs.

Read only the reference needed now:

- [Platform dispatch](references/platform_dispatch.md): native Codex/Claude role selection, configured models/effort/permissions, or the isolated Codex runner. Do not infer effective settings from a declaration.
- [Long runs](references/long_runs.md): training, synthesis, or hardware capture; exact command, blocking completion, checkpoints, cancellation, and terminal evidence.
- [Resource detector](references/resource_detector.md): local concurrent compute or signs of resource pressure. Run `scripts/detect_resources.sh` before launching that compute and use a fresh result; a read-only remote agent alone does not justify local resource probes.

Use one writer per shared checkout; parallel writers need isolated worktrees, disjoint ownership, and a merge plan. Allow at most one heavy local command at a time. A new resource recommendation applies to new work; do not cancel healthy work because it decreased. Low swap or a failed detector alone is not proof of pressure. A failed step blocks its dependents and cannot be reported as success.
