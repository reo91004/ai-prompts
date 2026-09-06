# Platform Dispatch


For native Codex delegation, set the exact `agent_type`; a task label does not select a role. In a spawn call that also sets role, model, or reasoning overrides, use `fork_turns = "none"` or a bounded positive turn count because current Multi-Agent V2 full-history mode rejects override-bearing calls. Without overrides, select the context range independently and allow `"all"` when full history is needed. Pass the agent's declared `model` and `reasoning_effort` when the tool exposes those fields. If this runtime hides the selector or model controls, run `scripts/run_codex_agent.sh <role> <task>` from this skill for an isolated Codex child, or report the limitation. Do not describe a generic child as the configured specialist.

For Claude Code, select the exact subagent type through the Agent tool or an explicit `@agent-name` mention. `CLAUDE_CODE_SUBAGENT_MODEL` and `CLAUDE_CODE_EFFORT_LEVEL` override the declared assignment when set, so mention them if they change what actually ran.

In both runtimes, never state that a child ran as a specific role, model, or effort unless the runtime showed it. Saying "unverified" is correct; asserting the declaration as fact is not.

## Cooperation

Use an available connector or `scripts/run_codex_agent.sh` for a concrete Codex contribution from Claude. Batch related questions and reuse a useful review. Do not require collaboration at every phase. If the other agent is unavailable, say so once and continue authorized work without claiming it participated.
