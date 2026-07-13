# Evidence Ledger: [work item title]

Deterministic checks record command and exit code. Claim-bearing entries add
the evidence contract fields (origin, purpose, blinding, measurement scope,
claim scope) from `evidence-gate/references/evidence_contract.md`.

## Deterministic Checks

| When | Command | Exit | Result summary |
|---|---|---|---|
| [ISO time] | `[command]` | 0 | [무엇이 확인됐는가] |

## Claim-Bearing Evidence

### [claim 요약]

- evidence_origin: [synthetic | simulated | measured]
- evidence_purpose: [diagnostic | claim_bearing]
- blinding: [not_applicable | unblinded | blinded]
- measurement_scope: [...]
- claim_scope: [namespace:value]
- Artifact: [경로 또는 로그 위치]
- Allowed statement: [증거가 지지하는 최대 서술]
- Blocked statement: [이 증거로는 주장할 수 없는 것]
