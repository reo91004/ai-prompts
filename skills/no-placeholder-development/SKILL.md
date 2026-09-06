---
name: no-placeholder-development
description: Use when implementing, refactoring, or debugging research code, especially where incomplete behavior or a silent fallback could corrupt a result.
---

# Complete, Simple Research Code

Implement the smallest complete behavior the current task needs. A script with ordinary functions is a valid finished result; use the standard library and existing code before adding a dependency or framework.

- Follow `references/placeholder_hardcoding_policy.md` for executable code and analysis scripts.
- Keep reproducibility state: seed, config, relevant environment/package versions, raw outputs, and their association with the run.
- Keep checks that catch concrete execution errors, wrong research results, equipment incidents, or user-data loss. Avoid duplicate shape/dtype checks, speculative exception hierarchies, and wrappers that merely reword a traceback; preserve an array or unit check when it catches a real mistake.
- Use `try`/`except` only for a real recovery or required cleanup. Never replace a failed experiment with synthetic data, zeros, a default metric, or a fake pass.
- Introduce shared abstractions when a second real caller needs them. Add configuration files, packaging, and workflow tools only when the current experiment benefits from them.
- Validate the changed behavior using the smallest relevant check; expand when a failure or a specific cross-cutting risk warrants it. Update nearby comments to describe current behavior and rationale, without repair history or unfinished markers.

Use `references/research_code_guard_policy.md` for the boundary between research integrity and production hardening. A requested path must work beyond its test fixture. Unsupported behavior must fail clearly; author-controlled internal helpers do not need general malformed-input defenses.
