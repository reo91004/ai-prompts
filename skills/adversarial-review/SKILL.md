---
name: adversarial-review
description: Use for critical review of a material claim or artifact, or to investigate an anomalous result or pessimistic assessment.
---

# Critical Review And Result Analysis

Establish what the evidence supports before testing the weakest inference. Keep criticism specific to the claim and recognize a contribution that is research-sufficient within its scope. Apply `review-budget` when starting an acceptance review if its scope and budget have not already been set.

For unexpectedly good or negative results, or pessimistic assessments, use `references/result_analysis.md`. This is causal investigation and remedy design; repeated acceptance review alone is not analysis.

Use the optional templates only when a structured written review helps. Existing artifacts and evidence pointers are sufficient input. Report `Required Fixes`, `Research-Sufficient`, `Optional Hardening`, and `Do Not Change` as relevant. Do not require every heading or invent a fault to fill one.

- A concrete wrong result, unsupported inference, failed relevant test, placeholder, or needless implementation complexity is a required fix.
- Missing production polish or experiments beyond the current claim are optional.
- When a claim is too broad, identify the narrower supported finding as well as the evidence needed to extend it.
- One semantic reviewer and at most one targeted delta re-review are the default. New evidence or a new causal hypothesis can justify further investigation under the user's task scope.

Needless implementation within the reviewed scope requires a fix, just as placeholder behavior does. Do not label a check needless when it protects a concrete result, equipment safety, or user data.

For substantive interpretation, use the relevant [shared research principles](../research-domain-router/references/research_principles.md). Investigate unexpectedly good and bad findings with `references/result_analysis.md`; compare plausible mechanisms and discriminating checks. Do not reserve causal investigation for negative results.
