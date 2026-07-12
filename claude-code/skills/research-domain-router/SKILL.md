---
name: research-domain-router
description: Use to decide which domain gates and reference rules apply to a research or development task.
---

## Use
Select all relevant domain gates before work begins. A task may require multiple gates. Keep Global Core policy in the global prompt, reusable domain procedure in skills, and repository-specific `.omo` state, stage names, equipment constants, thresholds, and attempt limits in the Project Overlay.

Route delegation to `resource-aware-orchestration`, semantic review to `review-budget`, and acceptance to `evidence-gate`. Add `hardware-capture-integrity` only when physical acquisition is in scope.

Read `references/domain_gates.md` only when relevant.

## Required output
Task type, relevant domains, required evidence, delegation decision and distinct deliverables, required skills, project-overlay inputs, and acceptance blockers.
