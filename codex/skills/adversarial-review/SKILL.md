---
name: adversarial-review
description: Use when reviewing code, papers, experiments, results, claims, diffs, logs, figures, or tables adversarially.
---

## Use
Attack the artifact, not the author. Use concrete evidence.

Use `templates/adversarial_review_packet.md` when asking Codex MCP or another reviewer to review. Use `templates/adversarial_review_report.md` when recording results.

A valid review must include verdict, scope, evidence, findings, missing evidence, required fixes, research-sufficient notes, optional hardening, do-not-change notes, and claim-control decision.

## Calibration
For research code, attack logic, evidence, reproducibility, and claim strength. Do not turn readable paper-idea validation code into production infrastructure unless the claim, data integrity, user safety, or destructive behavior requires it.

Classify review items:

- `Required Fixes`: logic errors, claim/evidence mismatch, missing provenance, missing seed/config/run binding, synthetic/measured confusion, fake-pass paths, missing artifacts hidden as success, data corruption risk, or destructive/user-data risks.
- `Research-Sufficient`: code that is readable, traceable, and adequate for the stated research claim even if it is not production hardened.
- `Optional Hardening`: internal argument validation, dtype/shape over-defensiveness, resource caps, TOCTOU defenses, duplicate revalidation, complex exception hierarchies, or framework/schema machinery that would mainly serve production use.
- `Do Not Change`: changes that would reduce readability, make scripts less explicit, or add generic infrastructure without strengthening the research claim.
