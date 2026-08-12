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
Implement the smallest solution that fully works. Simple is best: prefer a flat function over a class, a literal over a config entry, and a crash over a caught-and-rethrown exception. Do not add speculative abstraction, one-implementation interfaces, factories, registries, config for values that never change, `try`/`except` you cannot act on, or framework machinery before a second real caller exists. Prefer numbered stage scripts and a thin CLI over a mega-CLI with speculative flags or modes. Keep experiment parameters in config (YAML once `configs/` exists), never in CLI flags; CLI flags may only reference paths (`--config`, `--run`, `--out`). Over-engineering is as unacceptable as a placeholder: both are code that should not exist yet.

## Code That Grows

These are how a working file doubles in size. Each is a `Required Fix`, and each has exactly one fix:

- **Re-validating your own output.** Reading back a file this pipeline just wrote and re-checking every field. Validate at trust boundaries — an instrument, a vendor tool, a person — not between your own stages. Between stages check only what a wrong path or a stale file would break, which is identity and binding, not every key.
- **The same check in two places.** A shape or contract verified in a function and again in its caller. Delete one and keep the one nearest the data.
- **A guard that exists to satisfy a type annotation.** `if len(x) != 2: raise` so that `cast(tuple[A, B], x)` reads as honest. Loosen the annotation instead; the guard checks a value this code produced three lines earlier.
- **One `raise` for eight conditions.** A long `or` chain reporting "contract differs" says nothing when it trips, and hides which conditions can never fail. One condition, one message — then delete the ones that cannot fail.
- **A new guard beside the old one.** When adding a check, name the check it replaces and delete that one. A guard added without a deletion is the mechanism by which the file grew.

Before writing any check, state in one sentence the wrong result it prevents. If that sentence needs "in case" or "someone might," do not write the check.

Rigor lives in the experimental design — fresh data, a decision rule fixed before the data is seen, negative controls, an honest denominator — not in the number of `raise` statements. A reviewer never reads the code that re-checks your own JSON.
