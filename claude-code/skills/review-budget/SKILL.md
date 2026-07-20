---
name: review-budget
description: Use to decide whether semantic review is needed, bound its scope and rounds, and stop review churn.
---

## Review Necessity Gate

Use semantic review when a change affects architecture, security, user data, a research or benchmark claim, or final adversarial acceptance. Skip it for mechanical changes whose deterministic evidence fully establishes the stated result.

Before semantic review, require relevant deterministic checks to pass. A missing or failed required check blocks review approval.

## Deterministic Validation Budget

- Prompt or documentation-only changes: run one focused static or contract check. Do not run full suites or install regression unless executable behavior, installation, or generated artifacts changed.
- Focused code changes: run applicable syntax or type checks and the smallest targeted test that exercises the changed path.
- Installer, manifest, copy semantics, or executable-permission changes: add install regression. Integration migration runs only when integration code or its persisted state schema changed.
- Claim-bearing research, benchmark, security, hardware, or user-data-safety changes: run every deterministic gate required by the claim and evidence contract. Physical safety and capture-integrity checks apply to every physical capture, including diagnostic runs.

Do not rerun an unaffected passing suite after a narrow delta. Recheck the changed path and expand only after a failure or newly revealed cross-cutting risk. More available time or agents does not increase this budget.

## Budget

- Use exactly one semantic reviewer for a review round.
- Default to one full review and, after required fixes, one targeted review of the changed delta and affected evidence.
- Permit a third review only when a new blocker appears, scope or acceptance criteria change, or the user explicitly requests it.
- Stop when no `Required Fixes` remain. `Optional Hardening` alone is not a reason for another round.

## Review Packet

Provide claim, artifact slice, deterministic evidence, evidence contract, acceptance criteria, prior required fixes, current delta, and remaining risks. Require verdict, evidence, missing evidence, categorized findings, required fixes, and claim-control decision.
