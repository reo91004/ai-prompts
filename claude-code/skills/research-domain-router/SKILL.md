---
name: research-domain-router
description: Use to decide which domain gates and reference rules apply to a research or development task.
---

## Use
Select only domain gates required by the current task or claim before work begins. A task may require multiple gates. Keep Global Core policy in the global prompt, reusable domain procedure in skills, and repository-specific `.omo` state, stage names, equipment constants, thresholds, and attempt limits in the Project Overlay.

Route delegation to `resource-aware-orchestration`, semantic review to `review-budget`, and acceptance to `evidence-gate`. Add `hardware-capture-integrity` only when physical acquisition is in scope.

Read `references/domain_gates.md` only when relevant.

For a small task, make the routing decision directly; do not produce a separate routing report or load every gate. When a routing explanation helps, state only the relevant domains, evidence needed, and unresolved decision.
