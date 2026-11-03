---
name: crucible
description: Run an explicitly requested bounded research loop with automatic conditional model review, or start an on-demand evidence debate. Uses the external Crucible controller for persistent recovery and validated next-experiment decisions.
---

# Crucible Research Loop

Crucible is a separate engine. The default ai-prompts installer finds an existing checkout under HOME or downloads it to `~/Crucible`, then records the connection. The launcher reuses that path and can rediscover moved checkouts under HOME. `CRUCIBLE_ROOT` and an installed CLI on PATH remain explicit overrides. Cache, virtual-environment and kit-backup directories are excluded from search; multiple matches require an explicit choice. This skill works from OpenCode, Claude Code, and Codex. The engine owns execution and state; the host owns the research scope.

Use this skill's `scripts/crucible.sh --project <research-project> <command>`. Read the engine README before preparing a real project's `.crucible/config.json`. `init` creates a synthetic teaching example; use a fresh directory for it. A real project needs declared experiment argv, typed parameter bounds, inputs, required artifacts, its evaluator, budgets, and explicit model IDs from the available catalog. Reuse existing research cards and raw results.

## Starting from a research request

The user supplies the goal, meaningful outcomes/stop conditions and resource budget. Inspect the project to identify its actual experiment command, outputs and evaluation code; prepare the configuration and a project-specific evaluator yourself. The user does not need to hand-write JSON or issue a debate command after every result. Validate the contract and use the available model catalog for explicit model IDs. Ask only for essential scientific choices or limits that cannot be inferred. Keep input changes within authorized project scope.

Once `run --background` starts, the controller evaluates each result. Evaluator events anomaly/regression/stagnation/theory_conflict trigger independent review automatically, then a validated next experiment. Normal results with an explicit next step skip discussion. This applies to experiments launched through Crucible. It does not discover arbitrary external sessions or automatically parse every terminal log; do not relaunch a live job to bring it under control.

## Explicit debate

For `/crucible debate <question>` or a user request to discuss now, use `debate --question <question> --background`, with repeated `--evidence <project-relative-file>` when needed. If evidence flags are omitted, it snapshots the latest completed run if available. A question-only discussion must be labeled as lacking empirical evidence. Cases have separate bounded model-call budgets and records under `.crucible/debates/<id>/`; they do not launch experiments, change the active loop's next decision, or cancel running work. `debate --resume <id>` reuses the captured question/evidence and completed calls; `--retry` applies only to known failures.

After `link-opencode`, `/crucible-debate <question>` dispatches the native tool with action=debate. Otherwise use this shared launcher from either OpenCode or Claude Code. Summarize the saved conclusion, unresolved points, next checks and evidence limits; manual discussion is not automatic authorization to execute its suggestions.

- `validate` checks the project contract; `doctor` checks binaries without model calls.
- `run --background` starts the durable worker; `status` reports ownership, progress and next action. Keep one writer and do not edit active experiment inputs or configuration.
- `link-opencode` installs a project-local V2 bridge without modifying global settings. Reload that project's OpenCode session, then use its `crucible` tool. `deliver` forwards durable events and acknowledges only successful delivery; it does not certify experiment validity.
- `pause` and `stop` prevent subsequent work and leave active experiments running. `resume --background` continues existing work. `cancel` explicitly requests active job cancellation; a model call obeys the flag at its next boundary and remains timeout-bounded.
- `reconcile` checks retained receipts and process identities after interruption. `retry` explicitly authorizes a failed stage and retains earlier failure evidence. Uncertain launches are never silently rerun.
- `events`, `ack <id>`, and `report` expose durable records. Do not create an LLM status-polling loop or launch a duplicate worker while waiting.

Reviewers see supplied evidence only. Models propose registered experiments and bounded parameters; they do not supply executable shell. A supported negative finding is valid. Do not reinterpret missing evidence, a failed call, a model vote, or the synthetic example as a successful research result. Physical acquisition and arbitrary code editing are outside this controller's execution contract.
