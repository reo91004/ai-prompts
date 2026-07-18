# Capture Run Layout And Output Contract

Every claim-bearing or diagnostic hardware capture writes one self-contained run
directory. The layout, the three required JSON documents, the diagnostic image,
and the logs below are the standard the capture must always produce — this is the
reproduction evidence, not optional hardening, so it is never trimmed.

The SMAUG-T / poly2msgleaks run
`20260707-102100-smaugt-pack-twice-top1-latetrig12` is the worked example. Its
scheme-specific array names (`decoded_readback.npy`, `pair_states.npy`, …) are
illustrative; the reusable contract is the directory shape, the manifest fields,
and the claim-scope discipline.

## Run Directory

```text
runs/<YYYYMMDD-HHMMSS>-<slug>/
├── traces.npy                 # float32 [N, samples] — raw measured traces
├── <label/decoded>.npy        # per-trace labels and decoded values the analysis needs
├── manifest.json              # provenance + artifact roles + claim scope (see below)
├── capture_summary.json       # backend + rig_quality (see below)
├── capture_diagnostic.png     # traces visualization (see below)
├── blocked.json               # ONLY on failure, instead of a fake-success manifest
├── config.yaml                # the exact config used (hashed into manifest)
├── queries/queries.json       # prepared inputs, bound by sha256 in provenance
├── logs/
│   ├── capture.log            # scope settings (before→after), per-attempt events
│   ├── prepare_queries.log
│   ├── analysis.log
│   └── report.log
├── analysis/                  # written by the analysis step, not capture
│   ├── metrics.json
│   └── report.md
└── report/
    ├── summary.json
    └── summary.md
```

A run is complete only when `traces.npy`, `manifest.json`, `capture_summary.json`,
and `capture_diagnostic.png` all exist and the manifest lists them. A failed
capture writes `blocked.json` and stops; it never writes a partial manifest that
reads as success.

## manifest.json

Top level:

- `run_id`, `scheme`, `stage`, `backend` (`hardware` | `simulation`)
- `seed`, `config_path`, `config_sha256`, `git_commit`
- `started_at_unix`, `finished_at_unix`, `status` (`ok` | `blocked`)
- `host` (`platform`, `python`), `tool_versions`
- `claim`, `claim_scope`, `claim_allowed[]`, `claim_not_allowed[]`
- `artifacts[]` — filenames
- `artifact_roles[]` — one entry per artifact:
  `{filename, role, sha256, shape, dtype, size_bytes, claim_scope}`
- `artifact_sha256{}` — filename → sha256 (mirrors `artifact_roles`)
- `provenance{}` — everything that binds the measurement to what produced it:
  - `firmware`: `hex` / `elf` / `lss` / `build_manifest`, each `{path, sha256}`
  - `host`: `so` / `build_signature`, each `{path, sha256}`
  - `prepared_queries`: `{schema, path, sha256, query_count, helper{params, required_symbols, sha256}}`
  - `target_board`, `command_route`, `tool_versions`
    (`chipwhisperer`, `picosdk`, `numpy`, `python`, …)

`claim_not_allowed` always includes the overclaims this run must not support
(`key_recovery`, `full_key_recovery`, `scheme_break`,
`measured_d2_d3_success_without_gate`). `claim_scope` distinguishes diagnostic
from claim-bearing so a diagnostic dataset can never be read as a proven result.

## capture_summary.json

```json
{
  "backend": "hardware",
  "query_count": 2048,
  "stage": "pack_twice_boundary",
  "rig_quality": {
    "auto_trigger_ms": 5000,
    "timebase": 1, "interval_ns": 2.0,
    "sample_count": 24000, "pre_trigger": 500,
    "power_scope": "picoscope_3000a", "power_channel": "A", "power_range": 4,
    "trigger_channel": "B", "trigger_range": 7, "trigger_threshold_mv": 1000,
    "power_std_mean_mv": 8.74, "power_std_min_mv": 8.47,
    "trigger_swing_mean_mv": 405.45, "trigger_swing_min_mv": 390.56,
    "overflow_count": 0
  }
}
```

`trigger_swing_min_mv` and `overflow_count` are the fields the first-arm quality
gate reads; keep them in every capture. `trigger_threshold_mv` records the value
actually passed to the SDK — fix its unit (ADC count vs mV) in provenance, since
the legacy PicoScope path passes this integer straight to the driver.

## capture_diagnostic.png

Written by a `write_capture_diagnostic(path, traces, labels)`-shaped helper, DPI
~140, title `Measured …diagnostic (<run-id>) — <N> traces, SNR <x>, MI <y> bit`.

- With per-trace labels: a 2×2 grid —
  (a) per-sample count-SNR with the POI window and peak marked;
  (b) mean trace by label around the POI;
  (c) POI-integral feature by label (violin/strip);
  (d) mean POI feature vs label.
- Without labels: a 2×1 fallback (raw/mean trace) so a run still gets a visual.

The image is a diagnostic aid, and its title must say so — SNR/MI on a diagnostic
capture is not a leakage or recovery claim.

## logs/

Each pipeline step appends its own log. `capture.log` records scope
configuration as `setting  changed from <old> to <new>` plus per-attempt trigger
swing, overflow, ACK, and accept/reject. Progress during the trace loop is shown
with `tqdm(..., file=sys.stderr)` so stdout stays reserved for the final artifact
path.

## Reusable Helper Shape

A small IO module keeps every run consistent (see `p2mlab/io.py`,
`p2mlab/plots.py` in the reference repo). You do not have to adopt this exact
library — but whatever you write should provide these functions so the contract
above is produced the same way every time, rather than re-derived per script:

- `sha256_file(path) -> "sha256:…"`, `sha256_bytes(bytes)`
- `write_json(path, data)` — `indent=2, sort_keys=True`, trailing newline
- `save_np(path, arr)`
- `start_manifest(config, config_path, out_dir, status=…)` — seeds run_id / scheme
  / stage / backend / seed / config hash / git commit / host / tool_versions and
  the default `claim_not_allowed`
- `finish_manifest(manifest, out_dir, artifacts, status="ok")` — fills
  `artifact_roles` (sha256 + shape + dtype + size + scope) and `artifact_sha256`,
  writes `manifest.json`
- `write_blocked(out_dir, config, config_path, reason, provenance=…)` — writes
  `blocked.json` on any failure instead of a fake-success manifest
- `write_capture_diagnostic(path, traces, labels)` — the PNG above

Keep this module small: it standardizes provenance and output, it is not a place
to grow production-style validation or a plugin framework.
