---
name: code-comment-hygiene
description: Use whenever reading, editing, refactoring, reviewing, cleaning, or accepting code that contains comments, TODOs, FIXME notes, legacy explanations, or implementation history.
---

## Purpose
Keep code comments truthful, current, and useful.

Read `references/comment_hygiene_policy.md` before accepting any code change that touches comments or legacy code.

## Required Checks
- Compare comments against executable behavior.
- Remove or rewrite stale, misleading, speculative, or historical comments.
- Reject TODO/FIXME/HACK/temporary comments in accepted code unless the user explicitly requested a planning stub.
- Move unfinished work into carry-over docs or issue tracker instead of leaving TODOs in source.
- Treat comments as explanation only, never as implementation evidence.

## Output
When reviewing, report:
- stale comments found;
- comments updated or removed;
- TODO/FIXME/HACK items moved to carry-over;
- any remaining comment risk.
