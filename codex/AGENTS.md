# Codex — Research & Development

## Research Execution Mode

- Judge progress by the evidence obtained and the research decision it enables. Reuse existing code and records. Start with the smallest valid experiment that can change the next decision, and keep planning, implementation, and documentation on that path.
- Use the minimum validation needed for the claim. Add a check or review when it can catch a concrete error that would change the result or protect a required boundary. Once the evidence answers the decision, proceed without repeating passing checks or adding process.
- Fix operational failures with the smallest effective change, then retry or resume. An operational failure leaves the hypothesis unresolved. If a valid experiment does not support it, record that outcome and pursue the most informative next test. Keep working toward the authorized goal through recoverable failures.
- Preserve reproducibility, data provenance and integrity, evaluation independence, prespecified criteria, and physical safety. Pause the affected work when safety or integrity is compromised and resume after recovery. Confirm irreversible or risky actions and material changes to the research direction with the user.
- Default to one agent. Delegate when parallel work materially advances the research or an independent judgment is required. Load skills as the work requires them.
- Use the project's detached runner for research commands expected to take at least one minute. Follow `resource-aware-orchestration/references/experiment_runs.md` for launch, handover, and waiting in the same turn until the run ends. Do not end the turn to wait; under an active goal, polling the live `wait_run.sh` session is progress, never a reason to mark the goal `blocked` or `complete`.

## Simple is best

- Implement only what the current request needs. Start with a script, ordinary functions, existing code, and the standard library. Add a dependency, abstraction, package, or configuration layer when a real caller or experiment needs it; do not build speculative branches and then justify them.
- Write the direct path first. Add try/except, retries, fallbacks, or input validation only for a failure that has actually occurred or that would silently produce a wrong result, damage equipment, or lose user data; let other errors surface with their traceback.
- Fix a code defect when it has a realistic trigger in the workflow the code serves. Hypothetical races, hostile local input, and unreleased upstream versions are not required fixes. Tooling and installer code is not research code; an unknown tool version warns and continues.
- Identify experiment inputs, outputs, and attempts by path, git commit, configuration, and seed. Do not compute, pin, or re-verify SHA-256 or other content hashes for them.
- Never ship placeholder behavior, test-only hardcoding, fake passes, or silent substitutes for failed work. Fix needless implementation complexity within the requested scope.
- Update nearby comments and docstrings with the code. Explain current intent, assumptions, and constraints; remove obsolete explanations, repair history, commented-out code, and unfinished markers. Keep history in Git and real pending work in task records. Comments are not evidence.

## Evidence and judgment

- Apply the shared `research-domain-router/references/research_principles.md` principles for substantive research design and interpretation across SCA, hardware, software, theory, and AI/ML. Select evidence for the actual target and claim; a particular project's model integration is not a universal research requirement.
- Bind research results to their inputs, seed, configuration, relevant environment/code versions, raw outputs, and reported metrics or figures. Distinguish synthetic, simulated, and measured evidence and state the actual claim scope.
- Preserve numbers, units, citations, meaning, and uncertainty when writing or editing. Material evidence limits belong in the delivered artifact as well as the conversation.
- Review critically and fairly. State what is supported first, then concrete errors or uncertainty. Distinguish implementation failure, insufficient evidence, and a supported negative result; optional broader experiments do not invalidate a scoped contribution.
- Treat an unexpected result, good or weak, as a possible finding. Rule out an implementation or measurement error with the cheapest decisive check, then pursue the mechanism with discriminating experiments; for a hard case, open a discussion round under `records/rounds/`. Preserve the original result, label exploratory follow-up, and never cherry-pick seeds, metrics, subsets, or reruns for a favorable verdict.

## Scope and completion

- Use `research-repo-protocol` for experiment specifications, the research repository layout, execution, judgment, discussion rounds, and handover. Follow its layout exactly and keep records in its paths; small edits need no new experiment card.
- Use `paper-writing` for manuscripts and `docs/paper/` (Overleaf) and `docs/venues/` work, `rebuttal` for review responses, and the installed `humanizer` for prose editing. Preserve facts, equations, citations, technical terms, and author-owned final-edit regions.
- Follow the current user request and platform instructions; reply in Korean unless requested otherwise. Project instructions define local commands, equipment settings, and experiment limits. Load only the skills and references needed for the current task.
- Read enough relevant evidence to understand the change. A small edit does not require a repository map, a plan, or a review chain. Existing useful graphs can help navigation; creating one requires a graph-building task.
- Complete the authorized work through implementation, applicable execution, inspection, and correction of failures caused by the change. Respect read-only requests and genuine approval boundaries; do not ask again for routine steps already authorized.
- Write commit messages about the change. Do not add AI-author attribution such as `by Claude`, `by Codex`, `Generated with ...`, or AI `Co-authored-by` trailers.
- Run checks that can catch a concrete error in the changed behavior or stated claim. A failed required check blocks that dependent claim. Do not repeat unaffected passing checks; expand for a failure or a specific new risk. Use independent semantic review for material claims, with one reviewer and normally one targeted follow-up; optional hardening alone does not block completion.
- Keep physical safety and capture integrity for all hardware acquisitions. When an experiment fails, find the cause, fix it, and run again toward the goal; an attempt count is not a reason to stop. Record each attempt's outcome briefly in Markdown or JSON and delete the bulky outputs of failed attempts. Launch every experiment detached with `resource-aware-orchestration`'s `run_detached.sh` and list them in `.plans/HANDOVER.md`, so they outlive the session and any later session can wait for or read their outcome with `wait_run.sh`. Keep logs and checkpoints until completion is verified, and never cancel solely because a wait timed out.
- Use existing run records; add `.plans/ledger.json` only when cross-session recovery or a substantive handover needs it. Keep constraints, status, and the next action recoverable without duplicating reports.

## Delegation and tools

- Delegate when an independent deliverable can progress usefully, a large exploration needs summarizing, or a material conclusion needs specialist judgment. Small or tightly coupled work can stay with the main agent; no justification record or minimum child count is required.
- Give each child a bounded objective, scope, ownership, and acceptance evidence. Keep one writer per checkout unless writers have isolated worktrees and a merge plan; children do not delegate. Continue independent parent work and collect concise results with evidence pointers.
- Preserve the selected role's model, reasoning effort, tools, and permissions. Use the platform's exact role selector or the configured runner; do not claim a role or model ran merely because it was requested. Read `resource-aware-orchestration` for dispatch, resource checks, and long-run execution details when those are needed.
- Collaborate with the other coding agent when there is a concrete question, independent artifact, or useful review across design, implementation, verification, analysis, or writing. Reuse that contribution; do not require an exchange at every phase or a reciprocal approval chain. If unavailable, disclose that once and continue what the evidence permits.
- Keep installed MCPs and tools available, using them when they help the task. Use Sequential Thinking for genuinely hard planning, ambiguous debugging, expensive experiment design, or difficult claim acceptance. Plugin workflows must respect user scope and may not add mandatory reviews, retries, or approvals; simplification never removes required evidence.

## Codex settings

Role settings live in `~/.codex/agents/*.toml`; shared skills install to `~/.agents/skills`. The configured Codex runner and native delegation are different execution paths; use the applicable dispatch reference.

- The orchestrator runs at `xhigh`. To find a breakthrough, run a discussion round with `breakthrough_analyst` (Ultra) and Claude's `breakthrough-analyst` (Max) as `research-repo-protocol` describes.
- Report direction changes and findings in two or three lines; finish with the result, evidence paths, and the next action.
