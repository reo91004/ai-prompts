---
name: hardware-capture-integrity
description: Use for physical hardware acquisition, instrument setup, trigger integrity, capture provenance, and raw artifact preservation.
---

## Inputs

Read equipment-specific thresholds, warm-up duration, preflight procedure, retry or attempt limit, and output location from the Project Overlay or experiment config. If a required value is absent, stop the affected capture instead of inventing it.

## Capture Contract

- Bind instrument, probe, board, target, firmware, bitstream, host software, config, calibration, and clock/trigger settings to the run artifact using versions or hashes where available.
- Complete the configured warm-up and preflight before claim-bearing acquisition.
- Record trigger condition, expected and observed event counts, sampling settings, physical attempt number, operator-visible failures, and all configuration changes.
- Never hide, renumber, discard, or silently retry a physical attempt. Preserve raw artifacts from every claim-bearing attempt according to the Project Overlay.
- Keep diagnostic captures distinct from claim-bearing captures and classify both with the evidence contract.

## Run Output Contract

Every capture writes one self-contained run directory with the same shape so the
logging, JSON, and diagnostic image come out consistent every time — this is
reproduction evidence, never trimmed. Required outputs:

- `traces.npy` (float32 `[N, samples]`) plus the per-trace label/decoded arrays the analysis needs;
- `manifest.json` — provenance (firmware/host/prepared-query hashes, tool versions, target board), `artifact_roles[]` (filename, role, sha256, shape, dtype, size, claim_scope), `artifact_sha256`, and `claim_scope` / `claim_allowed` / `claim_not_allowed`;
- `capture_summary.json` — `backend` and `rig_quality` (trigger swing min/mean, power std, overflow count, sampling settings, thresholds);
- `capture_diagnostic.png` — traces visualization (2×2 with labels: per-sample SNR + POI, mean trace by label, POI feature by label, feature-vs-label; 2×1 fallback without labels), titled as a diagnostic;
- `logs/` — one log per step (`capture.log` records scope settings before→after and per-attempt swing/overflow/ACK/accept-reject);
- on failure, `blocked.json` — a blocked manifest, never a partial manifest that reads as success.

Show trace-loop progress with `tqdm(..., file=sys.stderr)` so stdout stays reserved for the final artifact path. Full schema and the reusable helper shape (`start_manifest` / `finish_manifest` / `write_blocked` / `write_capture_diagnostic`, kept small — not a framework) are in `references/capture_run_layout.md`.

## Pre-Capture Sequence (first-arm safe)

To avoid the first-trigger miss on external-scope + MCU-GPIO rigs, follow the fixed order and never condition it on results: `open → audit-only warm-up (one shot, eligible=false, reason=first_arm_warmup) → deterministic reset/prezero → prepare actual query → eligible capture`. Apply the same one-shot re-warm after any scope reconnect, reconfigure, or firmware flash.

- Reject noise-level trigger buffers at the swing gate; do not lower the gate to accept them.
- Verify full-window coverage separately: the buffer must hold the whole pulse (rising, falling, post-low), not just a rising edge.
- Allow at most one pre-declared quality retry; stop on two consecutive quality failures and on any major logical error, preserving the failed artifact and ledger row each time.
- Count warm-up, rejected, and retried captures as physical executions in the ledger and budget — never hide attempts to keep only successes.

Diagnosis, the toggle that confirms the miss, the warm-up contract, and a reuse checklist are in `references/first_trigger_recovery.md`.

## Output

Return run ID, provenance manifest path, preflight result, attempt ledger, raw artifact paths, evidence contract, deviations, failed steps, and claims that remain blocked.
