---
name: hardware-capture-integrity
description: Use for physical instrument/board acquisition, preflight, trigger integrity, and raw capture evidence.
---

# Physical Capture Integrity

Read the project's equipment settings, calibration, thresholds, warm-up/preflight, attempt limit, and output contract before any acquisition, including diagnostics. If a required safety or validity setting is missing, stop the affected capture instead of inventing it.

- Bind the instrument, probe, board, target, firmware/bitstream, host software, configuration, calibration, and clock/trigger settings to the run using versions or input identities where needed.
- Perform the configured safety checks and preflight. Check expected versus observed events, sampling/window coverage, units, overflow, and trigger quality where they determine capture validity.
- Record every physical execution, including warm-up, rejected captures, and retries. Preserve raw evidence, failures, configuration changes, and attempt indices; never silently retry, discard attempts, lower quality gates to pass, or retain only successes.
- Distinguish diagnostic and claim-bearing evidence and state what was actually measured. A successful acquisition alone does not establish a broader scientific claim.
- Keep each run's raw outputs, settings, logs, attempt record, diagnostic evidence, and explicit completion/failure state together or linked. A failed or partial run must not look complete. Use the project's existing format rather than introducing another schema.

Read only the applicable profile:

- [Trace run layout](references/capture_run_layout.md): the existing PicoScope/MCU trace profile, with its array/JSON/plot fields and helper examples. Preserve that complete contract in projects that use it; other rigs select equivalent evidence in their Project Overlay.
- [First-trigger recovery](references/first_trigger_recovery.md): external scope + MCU GPIO setups with a first-arm miss. Its fixed warm-up/reset/retry rules apply to that diagnosed setup, not every instrument.

Return the run ID, preflight outcome, provenance and raw-artifact paths, attempt record, deviations/failures, and the supported claim scope. General hardware-free analysis does not activate this physical-capture workflow.
