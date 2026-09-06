---
name: code-comment-hygiene
description: Use when changing commented code or explicitly reviewing comments, docstrings, TODOs, or mismatches between explanations and behavior.
---

# Code Comment Hygiene

Check comments and docstrings on the changed path against the current behavior. For an explicit comment audit, use the requested scope. Merely reading code with comments does not trigger a repository-wide audit or a separate reviewer.

Use `references/comment_hygiene_policy.md`. Remove stale history, duplicated explanations, and unused TODOs; retain the rationale needed to understand a scientific choice or non-obvious implementation constraint. Comments explain code and never prove a result.
