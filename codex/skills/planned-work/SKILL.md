---
name: planned-work
description: Use for multi-session or handover-driven work, or substantial claim-bearing work that needs recoverable state beyond existing run records.
---

# Persistent Work State

Read `.plans/ledger.json` first when resuming. It identifies the active work, user constraints, and plan. Small local changes do not need a ledger entry.

## Procedure

- Keep a short numbered checklist in `plan.md` for multi-step work. Record the user-authorized scope and next action. Authorization to do the task permits maintaining its plan; a separate plan approval is unnecessary.
- Preserve supplied handovers and user corrections when exact wording matters. Keep a fact or result in one place and link to it from the ledger or plan.
- Use existing logs and artifacts as evidence. Add `evidence.md` only when a small table of task, command, exit, and artifact pointers helps recovery. Store new raw logs in `evidence/t<NN>-<subject>.<ext>` when they belong to a plan step.
- Record a step as complete only when its relevant evidence supports that status. Update the work status and active pointer at completion or a genuine block.
- Review and merge an isolated agent's scoped diff, recording the outcome in the current work state. Do not create a separate merge-approval document.
- Refresh result documentation when evidence changes its conclusion or a milestone is reached. Do not mirror every process update into a report.

Templates are optional. Keep only documents that help resume the work or verify its result. This skill does not expand review, delegation, retry, or cancellation budgets.

## Ledger Format

`ledger.json` schema:

```json
{
  "schema_version": 1,
  "active_work_id": "2026-07-13-A-slug",
  "works": {
    "2026-07-13-A-slug": {
      "slug": "slug",
      "status": "active",
      "plan": "2026-07-13-A-slug/plan.md",
      "constraints": ["standing constraint stated by the user, verbatim"],
      "updated": "2026-07-13"
    }
  }
}
```

`status` is one of `active`, `paused`, `completed`, or `blocked`. `active_work_id` is a key in `works` or `null`. `constraints` holds only constraints the user stated; never record procedure rules the agent invented for itself. `plan` is relative to `.plans/`. Rewrite the whole file on every update so it always parses.

The day letter `<L>` is the first unused capital letter for that date (`A` for the day's first item, then `B`, `C`, …), so several plans opened on the same day keep a stable order. Create only the files the work actually needs; never scaffold empty templates. `.plans/` is local by default (the kit's global gitignore excludes it); a project that wants version-tracked plans adds `!.plans/` to its own `.gitignore`.
