# Research Code Guard Policy

Research code should be clear enough to audit and complete enough to support the stated claim. It does not need to become production infrastructure by default.

## Keep: Research Integrity Guards

Use fail-fast checks when accepting bad state would create fake science, fake confidence, or unreproducible evidence:

- synthetic and measured data must not be confused;
- dataset, trace, target, model, bitstream, config, seed, git commit, and run ID should be bound to outputs when they affect the claim — one commit hash for the code, not a per-artifact hash manifest;
- missing logs, metrics, checkpoints, plots, tables, or raw artifacts must not be silently replaced with fake values;
- `claim_scope` must distinguish simulation, synthetic evidence, real measurement, leakage detection, key recovery, reproduction, and production impact;
- random seeds and important config values must be recorded when they affect reported numbers;
- destructive operations or user-data/config rewrites need explicit path guards, backups, dry-runs, or refusal behavior;
- unsupported modes should stop clearly instead of producing plausible-looking results.

These guards are acceptance blockers because they protect the research claim.

## Delete: Production Hardening

Do not write these, and delete them when found, unless the user asks for production code, a public API, a service, security hardening, multi-user operation, or destructive/user-data behavior:

- `try`/`except` around code whose traceback is already the clearest failure report — let it crash;
- exhaustive internal argument validation in private research helpers;
- repeated dtype, shape, range, or schema checks after the data boundary is already controlled;
- re-reading output this pipeline just wrote and re-checking every field of it; between your own stages, verify only the identity and binding that a wrong path or a stale file would break;
- a second copy of a check that another function in the same pipeline already performs;
- DoS or resource caps for single-user offline scripts;
- TOCTOU defenses for non-destructive local experiment reads;
- complex exception hierarchies where a plain error is clearer;
- SHA-256 manifests, custody chains, or artifact sealing beyond what `git commit` already identifies;
- generic plugin registries, manifest validators, config migration systems, or framework machinery;
- broad defensive wrappers that make the experiment protocol harder to read.

These are `Required Fixes`, not optional hardening. An experiment script that crashes with a plain traceback is more auditable than one that swallows the error, so catching an exception you cannot act on actively harms the claim.

## Review Rule

When reviewing `raise`, validation, guards, or error handling, ask which specific wrong number, fabricated result, or broken logic it prevents from reaching a paper. If you can name it, keep the guard in full. If you cannot, delete it — code that only moves the experiment toward production style costs readability and buys nothing.
