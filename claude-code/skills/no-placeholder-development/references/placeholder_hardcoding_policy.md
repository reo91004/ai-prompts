# Placeholder, Fallback, Hardcoding, and Stale Comment Policy

Hollow code is banned because it is the shortest path from an LLM mistake to a wrong number in a paper. A stub that returns a plausible value, a fallback that hides a failed run, or a comment describing behavior the code never implements all produce output that looks like a result and is not one.

## Forbidden Unless Explicitly Requested as Planning-Only Stub

- TODO
- FIXME
- placeholder
- dummy
- stub
- temporary
- hack
- fake output
- fake metric
- fake test pass
- fixed return value that ignores real input
- fallback that hides real failure
- disabled assertion used to pass tests
- test-mode branch that bypasses logic
- magic constants without documented source
- comments claiming behavior that executable code does not implement
- obsolete comments that hide incomplete or unsafe behavior

## Allowed

- named constants traceable to a spec, paper, config, invariant, or protocol;
- explicit `NotImplementedError` or safe blocking behavior when a feature is truly unsupported;
- documented limitations in carry-over notes;
- short explanatory comments that match current behavior.

## Comment Rule

A TODO/FIXME/HACK in source code is treated as unfinished work unless the user explicitly requested a planning stub.

Old repair-history comments must be deleted or moved to documentation. Source comments should explain current behavior, not the history of how the code was repaired.

## Acceptance Rule

Do not mark a task as complete while placeholder logic, silent fallback, unsupported fake paths, stale comments, or TODO/FIXME/HACK markers remain in accepted artifacts.

Do not mark a task as complete while production hardening from `research_code_guard_policy.md`'s Delete list remains either. The two faults block acceptance equally: a placeholder is code that does too little, over-engineering is code that should not exist. Neither is a matter of taste, and neither may be deferred as optional.

For research code, combine this policy with `research_code_guard_policy.md`: fail-fast is required when it prevents fake evidence, and production-only defensive programming is deleted rather than deferred.
