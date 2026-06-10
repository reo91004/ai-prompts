---
name: no-placeholder-development
description: Use for all software development, research scripts, APIs, refactors, debugging, scope-appropriate implementation tasks, and any task where TODO, placeholder, fallback, or hardcoding risk exists.
---

## Policy
Do not produce or accept placeholder work.

Read `references/placeholder_hardcoding_policy.md` for strict rules. For research code, also read `references/research_code_guard_policy.md`.

Also use `code-comment-hygiene` when code contains comments, TODO/FIXME/HACK notes, legacy explanations, or stale implementation history.

For code changes: implement real behavior, avoid silent fallback, avoid test-only hardcoding, run relevant checks when possible, keep comments synchronized with current behavior, and document limitations honestly in carry-over notes.

For research code: keep research integrity guards that protect claims and provenance, but do not require production hardening that makes experiment scripts harder to read without strengthening the claim.
