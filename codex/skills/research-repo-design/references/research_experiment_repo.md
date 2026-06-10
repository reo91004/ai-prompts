# Research Experiment Repository Design

Use this reference when the repository is meant to validate a paper idea through experiments, measurements, or hardware runs. The goal is not to build a reusable library or generic framework; the goal is to make the experiment easy to run, audit, reproduce, and hand off.

## Core Principle

Keep the structure small and explicit:
- `scripts/` shows the experiment protocol.
- `<shortpkg>/` provides small reusable experiment functions.
- `target/` contains the measured implementation, firmware, host wrappers, and pristine vendor sources.
- `configs/` stores human-readable experiment defaults, not a framework schema.
- `docs/` contains the current source of truth.
- `runs/` contains complete run artifacts.

Prefer a slightly duplicated, readable experiment script over a hidden mega CLI or generic framework.

## Recommended Top-Level Structure

```text
<research-project>/
  README.md
  Makefile
  pyproject.toml
  requirements.txt
  .gitignore

  <shortpkg>/
    __init__.py
    targetref.py
    device.py
    scope.py
    capture.py
    labels.py
    segment.py
    analyze.py
    plot.py
    util.py

  scripts/
    00_selfcheck.py
    10_diagnose.py
    20_capture.py
    30_segment.py
    40_analyze.py
    50_controls.py

  target/
    firmware/
    host/
    vendor/

  configs/
    default.yaml
    pico.yaml
    cwlite.yaml

  docs/
    idea.md
    protocol.md
    labels.md
    threat-model.md
    handoff.md
    paper.pdf

  tests/
    unit/

  runs/
    .gitkeep
```

Use a root package with a short project-specific name. Do not introduce `src/` unless the repository is actually being packaged as a reusable library.

## Script And Package Boundary

Put experiment procedure in `scripts/`:
- numbered run order;
- hardware execution order;
- minimal `argparse`;
- print-based run logs;
- run naming and `runs/<id>` policy;
- selected path, mode, and verified/fast choices.

Put reusable experiment parts in `<shortpkg>/`:
- label formulas;
- statistics;
- device commands;
- scope capture helpers;
- host reference wrappers;
- segmentation;
- plotting;
- small JSON, NPZ, timing, and seed helpers.

Do not hide the full experiment protocol inside package code. Avoid package functions that encode the paper claim, hardcode a run name, or turn the whole workflow into one opaque call.

## Configs

Keep `configs/` only if the scripts actually read it. Config files are experiment notes with defaults, not schemas.

Accept this style:

```yaml
scope: picoscope3000a
board: f415
sample_count: 350500
pre: 200
post: 800
trigger_high: 100
trigger_low: 50
ack_timeout_ms: 30000
message: selected-event smoke
```

Use simple precedence: CLI value, then config value, then code default. Do not add allowed-key validators, nested dataclass schemas, version migrations, manifest-schema synchronization, or duplicate trigger-token maps unless the experiment truly requires them.

## Runs And Shareable Artifacts

Each run directory should be self-contained:

```text
runs/<timestamp>_<experiment>/
  meta.json
  raw/
    timing.csv
    labels.npz
    traces.npy
    trigger.npy
    signatures.bin
  work/
    segments.npz
  out/
    report.md
    control_report.md
    tvla_report.md
    rho2_*.png
    snr_*.png
```

Large raw traces may be excluded from shared bundles, but small audit artifacts should remain: `meta.json`, `raw/timing.csv`, `raw/labels.npz`, `work/segments.npz`, `out/*.md`, and `out/*.png`.

## Docs Policy

Keep only current source-of-truth documents in `docs/`:
- `idea.md`;
- `protocol.md`;
- `labels.md`;
- `threat-model.md`;
- `handoff.md`;
- the relevant paper or reference PDF when useful.

Move outdated design notes to `docs/archive/` or delete them. Archived notes must start with a warning that they are not the current protocol and must point to the current `docs/protocol.md` and `docs/handoff.md`.

## Makefile Policy

The Makefile should be a short command menu for the researcher, not a build framework. Typical targets:
- `host-lib`;
- `firmware`;
- `firmware-all`;
- `selfcheck`;
- `test`;
- `clean`.

`make selfcheck` should work from a fresh clone or source zip. `make test` should run hardware-free unit tests only. Hardware smoke tests should stay in explicit scripts.

## New Project Procedure

1. Write the research question and claim under test.
2. Create the small top-level structure.
3. Put pristine upstream or vendor code under `target/vendor`.
4. Add the host reference wrapper under `target/host` or `<shortpkg>/targetref.py`.
5. Add the minimal instrumented target under `target/firmware`.
6. Create `scripts/00_selfcheck.py` first.
7. Use `scripts/10_diagnose.py` to inspect timing and hardware behavior.
8. Make `scripts/20_capture.py` capture one selected internal event before expanding.
9. Make segmentation fail when edge counts or windows do not match expectations.
10. Add minimal rho2, SNR, MI, TVLA, and permutation controls before classifiers, recovery, or countermeasures.

## Refactoring Procedure

1. Preserve the old state in version control before moving files.
2. Write the current experiment question in one sentence.
3. Move only files directly needed by that question.
4. Remove generic config, manifest, schema, registry, and migration machinery first.
5. Split giant CLIs into a few numbered scripts.
6. Keep package functions only when scripts actually use them.
7. Move generated artifacts into `runs/`.
8. Keep only current protocol and handoff documents at the docs root.
9. Keep small hardware-free tests for labels, segmentation, and statistics.
10. Record real hardware evidence as timing CSVs and reports.

## Avoid

- generic frameworks for every possible experiment;
- config schema versioning;
- manifest migration systems;
- plugin registries;
- production-style provenance validators;
- abstract class hierarchies before the experiment needs them;
- mega CLIs that hide the experiment order;
- synthetic framework work before real measurement.
