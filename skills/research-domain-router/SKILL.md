---
name: research-domain-router
description: Use when a research task crosses domains or its required evidence is unclear.
---

## Use
Select the domain checks needed for the current claim. Keep reusable procedures in skills and project commands, stages, equipment constants, thresholds, and attempt limits in the Project Overlay.

Use the applicable domain skill directly when the domain is already clear. Read [domain gates](references/domain_gates.md) to resolve overlapping or uncertain requirements. This is not a prerequisite for ordinary code edits.

For substantive research design, interpretation, or novelty assessment, apply the relevant [shared research principles](references/research_principles.md). They cover research generally; the evidence required depends on the actual target and claim. Project datasets, publication targets, hardware constants, and record names remain project-specific.

Delegate through `resource-aware-orchestration` only when work benefits from delegation; use `review-budget` for semantic review and `evidence-gate` for accepting material claims. Physical acquisition also needs `hardware-capture-integrity`. Do not load all of these merely to route a task. Explain only the relevant domains, evidence, and unresolved decision when that explanation helps.

Use `research-repo-protocol` when coordinating a substantive experiment from specification through execution, evidence, judgment, and handover. Reuse its source-of-truth map instead of creating duplicate research records.
