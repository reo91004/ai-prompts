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

## Output

Return run ID, provenance manifest path, preflight result, attempt ledger, raw artifact paths, evidence contract, deviations, failed steps, and claims that remain blocked.
