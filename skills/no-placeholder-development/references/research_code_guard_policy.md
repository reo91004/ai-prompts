# Research Code Guard Policy

Research code should be clear enough to audit and complete enough to support the stated claim. It does not need to become production infrastructure by default.

## Keep: Research Integrity Guards

Use fail-fast checks when accepting bad state would create fake science, fake confidence, or unreproducible evidence:

- synthetic and measured data must not be confused;
- dataset, trace, target, model, bitstream, config, seed, git commit, and run ID should be bound to outputs when they affect the claim — one commit hash for the code, not a per-artifact hash manifest;
- missing logs, metrics, checkpoints, plots, tables, or raw artifacts must not be silently replaced with fake values;
- `claim_scope` must distinguish the conclusions relevant to the domain, including simulation versus measurement and component versus system claims; use leakage/recovery categories only for claims that need them;
- random seeds and important config values must be recorded when they affect reported numbers;
- destructive operations or user-data/config rewrites need explicit path guards, backups, dry-runs, or refusal behavior;
- unsupported modes should stop clearly instead of producing plausible-looking results.

These guards are acceptance blockers because they protect the research claim.

## Avoid: Unneeded Implementation

Do not introduce the following without a concrete need. Remove them within the requested scope when they add no useful behavior or protection. Keep any instance that prevents a real result error, equipment incident, or user-data loss; requested production or public-API behavior can also justify it:

- `try`/`except` around code whose traceback is already the clearest failure report — let it crash;
- exhaustive internal argument validation in private research helpers;
- repeated dtype, shape, range, or schema checks after the same invariant is already established; retain the check that catches a wrong axis, unit, truncated capture, or incompatible input;
- re-reading output this pipeline just wrote and re-checking every field of it; between your own stages, verify only the identity and binding that a wrong path or a stale file would break;
- a second copy of a check that another function in the same pipeline already performs;
- DoS or resource caps for single-user offline scripts;
- TOCTOU defenses for non-destructive local experiment reads;
- complex exception hierarchies where a plain error is clearer;
- per-output hash manifests, custody chains, or artifact sealing without a concrete reproducibility need; keep input identity and installed-file ownership records that prevent stale inputs or user-data loss;
- generic plugin registries, manifest validators, config migration systems, or framework machinery;
- broad defensive wrappers that make the experiment protocol harder to read.

Needless implementation is a `Required Fix` within the reviewed scope. Catching an exception without a real recovery or cleanup can hide the error; a plain traceback is preferable to a plausible-looking substitute result.

## Review Rule

When reviewing validation or error handling, name the specific wrong result, broken logic, equipment incident, or user-data loss it prevents. Keep that guard in full; omit or remove machinery that catches no such mistake and provides no requested behavior. Review the actual use, not just a keyword or code pattern.
