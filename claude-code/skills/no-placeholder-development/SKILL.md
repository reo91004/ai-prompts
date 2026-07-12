---
name: no-placeholder-development
description: Use for all software development, research scripts, APIs, refactors, debugging, scope-appropriate implementation tasks, and any task where TODO, placeholder, fallback, or hardcoding risk exists.
---

## Policy
Do not produce or accept placeholder work.

Read `references/placeholder_hardcoding_policy.md` for strict rules. For research code, also read `references/research_code_guard_policy.md`.

Also use `code-comment-hygiene` when code contains comments, TODO/FIXME/HACK notes, legacy explanations, or stale implementation history.

For code changes: implement real behavior, avoid silent fallback, avoid test-only hardcoding, run relevant checks when possible, keep comments synchronized with current behavior, and document limitations honestly in carry-over notes.

Treat `RESOURCE_*` failures and unsupported platform or tool states as explicit non-success results. Do not silently lower correctness requirements, omit a required child, or report a pass because resource detection failed. Sequential execution is the safe resource response when delegation remains necessary.

For research code: keep research integrity guards that protect claims and provenance, but do not require production hardening that makes experiment scripts harder to read without strengthening the claim.

## Scope And Minimalism
Implement the smallest solution that fully works. Do not add speculative abstraction, one-implementation interfaces, factories, registries, config for values that never change, or framework machinery before a second real caller exists. Prefer numbered stage scripts and a thin CLI over a mega-CLI with speculative flags or modes. Keep experiment parameters in config (YAML once `configs/` exists), never in CLI flags; CLI flags may only reference paths (`--config`, `--run`, `--out`). Over-engineering is as unacceptable as a placeholder: both are code that should not exist yet.
