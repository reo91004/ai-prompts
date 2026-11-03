---
name: research-repo-protocol
description: Design research repositories and coordinate experiments from question and specification to execution, evidence, judgment, and handover.
---

# Research Repo Protocol

Use the repository's existing conventions, environment, records, identifiers, and operational limits. Apply the relevant [shared research principles](../research-domain-router/references/research_principles.md). This protocol connects the research lifecycle; domain-specific validation remains in the applicable hardware, SCA, statistics, or AI/ML skill.

## Establish the record map

Identify the authoritative locations for the question and specification, raw evidence, code/configuration, judgment, discussion, events, current execution state, and next action. Link to them instead of copying facts between documents. A generated registry is a derived index. Read [directory roles](references/directory-roles.md) when unfamiliar with a structure; do not reorganize a repository to match an example.

Identify the source of user instructions as part of that map. Preserve supplied wording where it matters, and distinguish the original instruction from its project-specific interpretation and the reusable principle.

## Carry one question through its lifecycle

1. Reuse literature, reference implementations, completed experiments, and failure lessons.
2. Before a new experiment or a result-affecting method/evaluation change, update its card or equivalent specification. Link a stable ID to code, configuration, attempts, evidence, and judgment.
3. Record what the comparison identifies, hypotheses and controls, data roles and selection, metrics and units, uncertainty, decision rules, resource limits, failure handling, and completion artifacts. Fix confirmatory criteria before their results; record exploratory additions after an observation.
4. Implement and run checks that could prevent a concrete wrong result. Freeze running code/configuration and use the project's durable execution and event-monitoring path.
5. Verify exit status, expected artifacts, analysis completion, and evidence integrity before judgment. A PID, metadata file, log match, or accepted submission alone does not prove completion.
6. Record the strongest honest result, its contribution, the next decisive experiment, and unresolved uncertainty with remedies. Preserve previous results and corrections.
7. Update only records affected by the event and leave the next action recoverable.

Read [experiment lifecycle](references/experiment-lifecycle.md) for cards, attempts, and completion checks; read [handover](references/handover.md) for ownership transfer or work across sessions. Small edits that do not change the question, method, evaluation, or claim need no new card.

## Related responsibilities

[Repository structure](references/repository-structure.md) guides incremental layout choices; `planned-work` maintains an active recovery pointer when existing records are insufficient; `resource-aware-orchestration` owns dispatch, resources, waiting, and event delivery; `evidence-gate` and domain checks establish claim scope; `report-writer` and `paper-writing` produce their respective documents. Use these when their responsibility is needed, not as a mandatory skill chain.
