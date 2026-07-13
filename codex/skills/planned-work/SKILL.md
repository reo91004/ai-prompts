---
name: planned-work
description: Use for multi-session, claim-bearing, or handover-driven work to keep a user-inspectable plan and evidence ledger under .plans/.
---

## When To Use

Use this skill only when at least one of these holds: the work spans multiple sessions, a research or benchmark claim depends on it, the user supplied a handover document, or the user asked for a plan. Do not create a `.plans/` entry for small local edits, mechanical changes, or single-question tasks — the ledger is for work worth resuming and auditing, not for everything.

## Work Ledger

Keep one directory per work item inside the active project:

```text
<project>/.plans/
├── INDEX.md                     # one line per item: date, slug, status, next step
└── <YYYY-MM-DD>-<slug>/
    ├── handover.md              # the user's instructions, preserved verbatim
    ├── exploration.md           # files read, findings, assumptions, open questions
    ├── plan.md                  # the approved plan only — never drafts
    ├── evidence.md              # evidence ledger with contract fields
    └── carry-over.md            # unresolved items and required next evidence
```

Create only the files the work actually needs; never scaffold empty templates. `.plans/` is local by default (the kit's global gitignore excludes it); a project that wants version-tracked plans adds `!.plans/` to its own `.gitignore`.

## Procedure

1. If the user provided instructions or a handover document, copy them into `handover.md` verbatim before interpreting them. Requirements quoted later must trace back to this file.
2. Record exploration in `exploration.md` as you go: what was read, what was found, which assumptions remain unverified.
3. Build the plan with the host's plan mode, and Sequential Thinking MCP only when the problem is genuinely hard. Write only the approved plan to `plan.md` using `templates/plan.md`. When the plan changes, update the file and state the reason — the file always reflects the current plan, not its history.
4. Accumulate evidence in `evidence.md` using `templates/evidence.md`. Claim-bearing entries carry the evidence contract fields from `evidence-gate/references/evidence_contract.md` (origin, purpose, blinding, measurement scope, claim scope).
5. Run deterministic checks directly and record each command and exit code in `evidence.md`. Do not spawn an agent merely to run a command.
6. Request semantic review only per `review-budget` — one reviewer with the `adversarial-review` packet, and only when the change touches architecture, security, user data, or a claim.
7. Move unresolved work to `carry-over.md` in the `report-writer/templates/carry_over.md` format instead of leaving TODOs in code.
8. Update the item's line in `INDEX.md` when its status changes; mark it done when acceptance criteria are met.

## Bounds

This skill changes where work is recorded, not how much process it gets. The delegation contract, liveness rules, and review budget of the global core apply unchanged: one child is valid and none is often right, deterministic checks are never delegated for their own sake, there is exactly one semantic reviewer by default, and nothing is cancelled on elapsed time alone.
