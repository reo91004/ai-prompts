---
name: code-comment-hygiene
description: Use whenever reading, editing, refactoring, reviewing, cleaning, or accepting code that contains comments, docstrings, TODOs, FIXME notes, legacy explanations, or implementation history.
---

## Purpose
Keep code comments and docstrings truthful, current, minimal, and useful.

Read `references/comment_hygiene_policy.md` before accepting any code change that touches comments or legacy code.

## Required Checks
- Compare comments against executable behavior.
- Remove or rewrite stale, misleading, speculative, or historical comments.
- Reject TODO/FIXME/HACK/temporary comments in accepted code unless the user explicitly requested a planning stub.
- Move unfinished work into carry-over docs or issue tracker instead of leaving TODOs in source.
- Treat comments as explanation only, never as implementation evidence.
- Prefer no comment over a stale or obvious one; comment only why, assumptions, invariants, units, or provenance.
- Keep docstrings only on public or research-risky functions; do not docstring every function or restate type hints.
- Keep resource and review policy change history in documentation, not source comments. Comments may state only the current invariant or threshold provenance.
- When scanning for unfinished markers, distinguish policy examples and quoted forbidden terms from executable-source markers; report both categories separately rather than treating documentation examples as unfinished implementation.

## Output
When reviewing, report:
- stale comments found;
- comments updated or removed;
- TODO/FIXME/HACK items moved to carry-over;
- any remaining comment risk.
