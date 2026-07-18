# Evidence Ledger: [work item title]

Deterministic checks record command and exit code. Claim-bearing entries add
the evidence contract fields (origin, purpose, blinding, measurement scope,
claim scope) from `evidence-gate/references/evidence_contract.md`. Raw output
lives under `evidence/t<NN>-*`; this table only points to it — do not paste
result prose or a SHA manifest here.

## Deterministic Checks

| Task | Command | Exit | Artifact (evidence/…) | Result summary |
|---|---|---|---|---|
| t01 | `[command]` | 0 | `evidence/t01-baseline.log` | [무엇이 확인됐는가] |

## Claim-Bearing Evidence

### [claim 요약]

- evidence_origin: [synthetic | simulated | measured]
- evidence_purpose: [diagnostic | claim_bearing]
- blinding: [not_applicable | unblinded | blinded]
- measurement_scope: [...]
- claim_scope: [namespace:value]
- Artifact: [evidence/t<NN>-* 또는 canonical run 경로 — 값 복제 말고 참조]
- Allowed statement: [증거가 지지하는 최대 서술]
- Blocked statement: [이 증거로는 주장할 수 없는 것]
