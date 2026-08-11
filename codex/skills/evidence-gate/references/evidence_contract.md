# Evidence Contract

Every research or benchmark claim must carry a complete evidence classification. Development claims should use the same fields when the distinction is material.

## Required Fields

- `evidence_origin`: `synthetic` | `simulated` | `measured`
- `evidence_purpose`: `diagnostic` | `claim_bearing`
- `claim_scope`: a non-empty `namespace:value` identifier defined by the task packet
- `measurement_scope`: `isolated_primitive` | `instrumented_subpath` | `full_algorithm_path` | `full_kem_path` — required for measured evidence only

These three-to-four fields are the whole contract; they exist to stop a claim from outrunning what was actually run. Do not add ceremony fields that only describe process. The result must return the task packet's exact `claim_scope`; changing it requires a new task packet and review budget.

## Optional Field

- `blinding`: `unblinded` | `blinded` — record only when a human or model judgment selected, tuned, or scored the result. Omit it entirely for a deterministic measurement, where there is nothing to blind.

## Acceptance Rules

- Diagnostic evidence may guide debugging or experiment design but cannot directly support a claim-bearing conclusion.
- Synthetic or simulated evidence cannot support a measured-real-system claim.
- Evidence from an isolated primitive or instrumented subpath cannot support a full-algorithm or full-KEM claim.
- Unblinded selection or tuning must be disclosed and cannot be presented as blinded confirmation.
- Missing, malformed, or internally inconsistent fields block the affected claim.
- Before writing a result down, state in one line that the claim does not exceed the evidence origin, purpose, measurement scope, and claim scope. This is a self-check the author or agent performs; it does not require a separate reviewer.
