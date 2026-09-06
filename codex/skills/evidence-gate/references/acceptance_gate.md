# Acceptance Gate

1. The requested behavior or stated claim has inspectable artifacts and passes its applicable deterministic checks.
2. There are no placeholders, fake passes, or silent substitutions, and implementation stays as simple as the task permits.
3. Research results retain the configuration, seed, code/environment context, and raw outputs needed for reproduction. Domain-specific evidence matches the claim.
4. Comments, documentation, figures, and conclusions agree with the evidence.
5. Apply semantic review only when the Review Necessity Gate requires it. Fix concrete errors and unsupported claims; distinguish optional extensions from required fixes.
6. State the supported outcome first. Accept a scoped contribution or a supported negative finding when the evidence is sufficient for that conclusion.
7. If the finding is unexpectedly negative or a review pessimistic, investigate plausible causes and practical remedies before generalizing the failure. A hypothesis remains a hypothesis until tested.

The gate decides the current claim, not whether every possible experiment has been run. New evidence may reopen analysis; repeating a verdict without new evidence does not add confidence.
