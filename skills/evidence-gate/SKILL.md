---
name: evidence-gate
description: Use to accept a research result, benchmark, or material implementation/report claim against its evidence.
---

# Evidence Gate

Bind the conclusion to inspectable evidence and an explicit scope. Small edits use their relevant deterministic check; they do not need an experiment packet, work ledger, or semantic reviewer solely to say the edit is complete.

For research claims, use [the evidence contract](references/evidence_contract.md) and the applicable domain checks. Use [acceptance criteria](references/acceptance_gate.md) when deciding a material claim. Apply `review-budget` when independent semantic review is needed; do not reread its rules if already established for this task.

- A failed deterministic gate blocks the behavior or claim it tests. Preserve independent valid findings and continue unrelated work.
- Distinguish code failure, insufficient evidence, and a supported negative result. A completed experiment may establish that a method did not work under the tested conditions.
- Recognize research-sufficient results within their supported scope. Optional broader experiments are not required fixes.
- For an unexpectedly weak result, check plausible errors, alternative explanations, and remedies using the result-analysis guidance in `adversarial-review`; do not relabel failure as success.
