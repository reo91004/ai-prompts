# Research Code Guard Policy

Research code should be clear enough to audit and complete enough to support the stated claim. It does not need to become production infrastructure by default.

## Keep: Research Integrity Guards

Use fail-fast checks when accepting bad state would create fake science, fake confidence, or unreproducible evidence:

- synthetic and measured data must not be confused;
- dataset, trace, target, model, bitstream, config, seed, commit SHA, and run ID should be bound to outputs when they affect the claim;
- missing logs, metrics, checkpoints, plots, tables, or raw artifacts must not be silently replaced with fake values;
- `claim_scope` must distinguish simulation, synthetic evidence, real measurement, leakage detection, key recovery, reproduction, and production impact;
- random seeds and important config values must be recorded when they affect reported numbers;
- destructive operations or user-data/config rewrites need explicit path guards, backups, dry-runs, or refusal behavior;
- unsupported modes should stop clearly instead of producing plausible-looking results.

These guards are acceptance blockers because they protect the research claim.

## Simplify: Production Hardening

Do not require these as blockers unless the user asks for production code, a public API, a service, security hardening, multi-user operation, or destructive/user-data behavior:

- exhaustive internal argument validation in private research helpers;
- repeated dtype, shape, range, or schema checks after the data boundary is already controlled;
- DoS or resource caps for single-user offline scripts;
- TOCTOU defenses for non-destructive local experiment reads;
- complex exception hierarchies where a plain error is clearer;
- generic plugin registries, manifest validators, config migration systems, or framework machinery;
- broad defensive wrappers that make the experiment protocol harder to read.

These may be listed as optional hardening, not required fixes.

## Review Rule

When reviewing `raise`, validation, guards, or error handling, first ask: does this protect claim integrity, reproducibility, data provenance, or user data? If yes, keep it. If it only moves the code toward production style while reducing readability, simplify it or mark it optional.
