---
name: planned-work
description: Use for multi-session, claim-bearing, or handover-driven work to keep a user-inspectable plan and evidence ledger under .plans/.
---

## When To Use

Use this skill only when at least one of these holds: the work spans multiple sessions, a research or benchmark claim depends on it, the user supplied a handover document, or the user asked for a plan. Do not create a `.plans/` entry for small local edits, mechanical changes, or single-question tasks — the ledger is for work worth resuming and auditing, not for everything.

## Work Ledger

`.plans/ledger.json` is the machine-readable index of every work item, so a new session can recover which work is active and under what constraints without re-reading prose. Each item also has a directory:

```text
<project>/.plans/
├── ledger.json                  # active pointer + per-work status and constraints
└── <YYYY-MM-DD>-<L>-<slug>/     # L = A, B, C… in creation order within the day
    ├── handover.md              # the user's instructions, preserved verbatim
    ├── exploration.md           # files read, findings, assumptions, open questions
    ├── plan.md                  # the approved plan as a TODO checklist — never drafts
    ├── evidence.md              # evidence ledger (small table) with contract fields
    ├── carry-over.md            # unresolved items and required next evidence
    └── evidence/                # raw artifacts, named by the plan TODO they support
        ├── t01-baseline.md      # t<NN> = plan.md TODO number; the plan is the index
        └── t03-t2-reanalysis.log
```

Raw evidence files (logs, notes, dumps) go under `evidence/`, each prefixed with the plan TODO number it supports (`t<NN>-<subject>.<ext>`). The plan's numbering is the index, so there is no separate `INDEX.md`, no artifact-naming validator, and no wall-clock timestamp scheme. Do not create an `artifacts/` pile with cryptic names.

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

## Procedure

1. On resuming, read `ledger.json` first: find the `active` work, its constraints, and the first unchecked TODO in its `plan.md`. Continue from there rather than re-deriving context.
2. If the user provided instructions or a handover document, copy them into `handover.md` verbatim before interpreting them. Requirements quoted later must trace back to this file. Add the work to `ledger.json` with `status: active` and set `active_work_id`; when switching work, mark the previous one `paused`.
3. Record exploration in `exploration.md` as you go: what was read, what was found, which assumptions remain unverified.
4. Build the plan with the host's plan mode, and Sequential Thinking MCP only when the problem is genuinely hard. Write only the approved plan to `plan.md` using `templates/plan.md`, as the numbered TODO checklist below. When the plan changes, update the file and state the reason — the file always reflects the current plan, not its history.
5. Track progress in the `plan.md` TODO checklist as the single source: `- [ ]` not started, `- [x]` done, `- [~]` in progress, `- [!]` blocked. Numbers are stable identifiers. Mark an item `[x]` only after a deterministic check confirms it, and record that check in `evidence.md` — a checkbox is not evidence.
6. Keep `evidence.md` a small table (task → what was confirmed → command → exit → `evidence/` path) using `templates/evidence.md`. Put raw output in `evidence/t<NN>-*` and point to it; never paste result prose or a growing SHA manifest into `plan.md` or `evidence.md`. Claim-bearing entries carry the evidence contract fields from `evidence-gate/references/evidence_contract.md` (origin, purpose, blinding, measurement scope, claim scope). Run deterministic checks directly and record each command and exit code; do not spawn an agent merely to run a command.
7. Request semantic review only per `review-budget` — one reviewer with the `adversarial-review` packet, and only when the change touches architecture, security, user data, or a claim.
8. Move unresolved work to `carry-over.md` in the `report-writer/templates/carry_over.md` format instead of leaving TODOs in code.
9. When acceptance criteria are met, set the work's `status: completed` in `ledger.json` and point `active_work_id` at the next active work or `null`.

## Docs Are Updated At Milestones, Not Every Step

While work is in progress, write only `.plans/`. The paper-facing source of truth in `docs/` (`results.md`, `protocol.md`, `experiments/*`, as defined by `research-repo-design`) is refreshed in batch at a gate pass or milestone, not mirrored every step. A measured value lives once in its canonical artifact (`runs/…` or `docs/results.md`); `.plans/evidence.md` only points to it with the contract. When the user says "keep docs in sync," that means refreshing the `docs/` claim when a gate passes, not duplicating the process ledger's prose into `docs/`.

## Anti-Bloat

These surfaces bloated real long-running work; do not recreate them:

- `plan.md` stays a pure TODO checklist. Never stack artifact paths, SHA-256 pointers, or a running status narrative at its top.
- Do not create `STATUS.md`, `INDEX.md`, or an artifact-naming validator script. The current state is *derived* — `active_work_id` in `ledger.json` + the first unchecked TODO in `plan.md` + the last row of `evidence.md` — not a separate hand-maintained document.
- Store each piece of evidence once under `evidence/` and reference it; never copy result bodies between process documents.

This is about removing duplicated code/doc surface and improvised subsystems. It never means cutting the logging, seeds, provenance, or verification metrics that reproduction and the claim require — those stay in full.

## Bounds

This skill changes where work is recorded, not how much process it gets. The ledger and TODO checklist track state only; they never expand the delegation, review, retry, or cancellation budget. The delegation contract, liveness rules, and review budget of the global core apply unchanged: one child is valid and none is often right, deterministic checks are never delegated for their own sake, there is exactly one semantic reviewer by default, and nothing is cancelled on elapsed time alone.
