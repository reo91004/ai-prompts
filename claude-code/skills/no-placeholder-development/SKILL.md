---
name: no-placeholder-development
description: Use for all software development, scripts, APIs, refactors, debugging, production-quality implementation tasks, and any task where TODO, placeholder, fallback, or hardcoding risk exists.
---

## Policy
Do not produce or accept placeholder work.

Read `references/placeholder_hardcoding_policy.md` for strict rules.

Also use `code-comment-hygiene` when code contains comments, TODO/FIXME/HACK notes, legacy explanations, or stale implementation history.

For code changes: implement real behavior, add validation and error handling, avoid silent fallback, avoid test-only hardcoding, run relevant checks when possible, keep comments synchronized with current behavior, and document limitations honestly in carry-over notes.
