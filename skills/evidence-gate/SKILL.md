---
name: evidence-gate
description: Judge a material claim or change against its evidence - acceptance of a research result, benchmark, security, architecture, or report conclusion; critical review and its budget; investigation of an unexpectedly good or weak result or a pessimistic assessment. Not for mechanical changes that a deterministic check fully establishes.
---

# Evidence Gate

Bind the conclusion to inspectable evidence and an explicit scope. Establish what the evidence supports before testing the weakest inference, and recognize a contribution that is research-sufficient within its scope.

- For research claims, use [the evidence contract](references/evidence_contract.md) and only the [domain gates](references/domain_gates.md) the claim needs. Use [acceptance criteria](references/acceptance_gate.md) when deciding a material claim.
- A failed deterministic gate blocks the behavior or claim it tests. Preserve independent valid findings and continue unrelated work.
- Distinguish code failure, insufficient evidence, and a supported negative result. When a claim is too broad, name the narrower supported finding and the evidence needed to extend it.
- For an unexpectedly good or weak result, or a pessimistic assessment, use [result analysis](references/result_analysis.md): causal investigation and remedy design, not repeated verdicts. Do not relabel failure as success.

## Review necessity

Use semantic review when a change affects architecture, security, user data, a research or benchmark claim, or final acceptance. Skip it for mechanical changes whose deterministic evidence fully establishes the result. Relevant deterministic checks pass first; a missing or failed required check blocks approval.

Deterministic checks by change type:

- Prompt or documentation only: one focused static or contract check. No full suite or install regression unless executable behavior, installation, or generated artifacts changed.
- Focused code change: applicable syntax or type checks and the smallest test that exercises the changed path.
- Installer, manifest, copy semantics, or executable permissions: add install regression. Integration migration only when integration code or its persisted state schema changed.
- Claim-bearing research, benchmark, security, hardware, or user-data-safety change: every deterministic gate the claim and evidence contract require. Physical safety and capture-integrity checks apply to every physical capture, including diagnostics.

Do not rerun an unaffected passing suite after a narrow delta; expand only after a failure or a newly revealed cross-cutting risk. More available time or agents does not increase this budget.

## Review budget and result

- One semantic reviewer per round: one full review and, after required fixes, one targeted review of the changed delta. A third only for a new blocker, changed scope or acceptance criteria, or an explicit user request. A reviewer that refuses or returns nothing counts as no review.
- Give the reviewer the claim or requested behavior, the artifact slice, and the deterministic evidence; a separate packet document is optional.
- Report what is supported first, then `Required Fixes`, `Research-Sufficient`, `Optional Hardening`, and `Do Not Change`, omitting empty categories. Stop when no `Required Fixes` remain.
- A wrong number, an unsupported inference, a placeholder, or needless implementation complexity is a required fix; a code defect qualifies only with a realistic trigger in the workflow the code serves. Missing experiments beyond the claim, production polish, defensive hardening, and content hashing are optional. Do not label a check needless when it protects a concrete result, equipment safety, or user data.

The budget caps repeated verdicts on the same artifact, not causal analysis: new evidence or a new testable explanation justifies further investigation. A useful Codex review obtained while collaborating counts as the review, not a second approval chain. State the strongest supported finding and the next decisive check without premature pessimism.
