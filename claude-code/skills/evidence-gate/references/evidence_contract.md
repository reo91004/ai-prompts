# Evidence Contract

Every research or benchmark claim must carry a complete evidence classification. Development claims should use the same fields when the distinction is material.

## Required Fields

- `evidence_origin`: `synthetic` | `simulated` | `measured`
- `evidence_purpose`: `diagnostic` | `claim_bearing`
- `blinding`: `not_applicable` | `unblinded` | `blinded`
- `measurement_scope`: `not_applicable` | `isolated_primitive` | `instrumented_subpath` | `full_algorithm_path` | `full_kem_path`
- `claim_scope`: a non-empty `namespace:value` identifier defined by the task packet

`measurement_scope` is required and must not be `not_applicable` for measured evidence. The result must return the task packet's exact `claim_scope`; changing it requires a new task packet and review budget.

## Acceptance Rules

- Diagnostic evidence may guide debugging or experiment design but cannot directly support a claim-bearing conclusion.
- Synthetic or simulated evidence cannot support a measured-real-system claim.
- Evidence from an isolated primitive or instrumented subpath cannot support a full-algorithm or full-KEM claim.
- Unblinded selection or tuning must be disclosed and cannot be presented as blinded confirmation.
- Missing, malformed, or internally inconsistent fields block the affected claim.
- The semantic reviewer must explicitly state that the allowed statement does not exceed the evidence origin, purpose, measurement scope, and claim scope.
