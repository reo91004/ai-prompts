# Research Experiment Repository Design

Use this reference when a repository exists to test a research idea through experiments, measurements, model training, simulation, hardware runs, or side-channel traces. The goal is not to build a reusable framework first. The goal is to make the first real experiment easy to run, audit, reproduce, compare, and hand off.

A research repository proves a claim; it is not a product. A repository may grow large, but each added file must protect claim validity, reproducibility, or provenance. If a file only makes the work feel more like production, do not create it yet.

## Minimal Creation Rule

Create the smallest repository that can run the first real experiment.

Before creating any file or directory, classify it as one of:

- required for the first run;
- required for reproducibility of the first run;
- required for current documentation;
- optional later.

Create only the first three. Do not create empty future folders. For every file you create, state in one line why it is needed now. If the reason is "later," do not create it.

## Choose The Center

Keep the philosophy stable, but choose the center of the repository from the domain:

```text
Hardware / side-channel:  target/, capture + analyze, runs/
AI / ML:                  data (when real), train + eval, runs/
LLM / prompt evaluation:  prompts/, run_eval + judge, runs/ (save raw outputs)
RL:                       envs, policy + rollout, train + eval, runs/
Simulation / theory:      simulate + eval, runs/
```

Do not copy a hardware layout into an AI project because it worked for a hardware paper. Keep the roles and change the folders.

## Levels

Pick the lowest level that fits. Default to Level 1 unless the user asks for paper-artifact quality or the first run needs hardware, real data, or model-training stages.

### Level 0: Scratch Hypothesis

Use when the user needs to check whether an idea is plausible, often within a day, with no data, no baseline, and no paper artifact yet.

```text
README.md
requirements.txt
run.py
notes.md
```

Do not create `scripts/`, `configs/`, `docs/`, `tests/`, `data/`, `src/`, or any package unless the first run needs them. A small self-check inside `run.py` is enough.

### Level 1: Small Repeatable Experiment (default)

Use when the user needs repeated runs and saved results, but not paper-level rigor yet.

```text
README.md
requirements.txt
Makefile
experiment.py
eval.py
configs/
  base.yaml
runs/
  .gitkeep
docs/
  handoff.md
```

No package directory yet. No `data.py`, `model.py`, or `metrics.py` yet; split them out when they actually appear. Put the hypothesis and how-to-run in `README.md`.

### Level 2: Paper Experiment

Use as the default for paper-level experiments across AI/ML, hardware, side-channel, and simulation.

```text
README.md
requirements.txt        # or pyproject.toml, not both
Makefile
core.py
metrics.py
plot.py
scripts/
  00_smoke.py
  10_prepare.py
  20_run.py
  30_eval.py
  40_report.py
configs/
  base.yaml
  baseline.yaml
  experiment.yaml
runs/
  .gitkeep
docs/
  idea.md
  protocol.md
  results.md
  handoff.md
tests/
  test_core.py
```

Reusable logic lives in flat root modules (`core.py`, `metrics.py`, `plot.py`), not a package. Add `data/`, `target/`, `notebooks/`, or a package directory only when the domain needs it.

### Level 3: Grown Project

Use only after Level 2 becomes hard to navigate, with many datasets, models, trainers, or collaborators.

```text
README.md
pyproject.toml
Makefile
project_name/          # shallow root package, not src/project_name/
  __init__.py
  data.py
  model.py
  train.py
  eval.py
  metrics.py
  plot.py
scripts/
configs/
data/
runs/
docs/
tests/
```

Do not start at Level 3 unless the complexity already exists.

## The src/ Rule

Do not create `src/<package>/` for an initial research repository. It adds depth and a packaging feel the experiment does not need.

```text
Level 0-1:   flat files at repository root (run.py, experiment.py, eval.py)
Level 2:     flat root modules (core.py, metrics.py, plot.py)
Level 3:     one shallow root package, e.g. project_name/
src/<pkg>/:  only when packaging, distribution, or import isolation is an explicit goal
```

## Domain Defaults

Start each domain small and expand only on a trigger.

### AI / ML

```text
README.md
requirements.txt
Makefile
train.py
eval.py
configs/
  baseline.yaml
  experiment.yaml
runs/
  .gitkeep
docs/
  idea.md
  handoff.md
```

Expand later: `data.py` when loading exceeds roughly 50 lines; `model.py` when the model makes `train.py` hard to read; `metrics.py` when there are two or more metrics or they are shared with the baseline; `plot.py` when figure regeneration matters; `scripts/` when stages separate.

Do not create from the start: `callbacks/`, `trainers/`, `registries/`, `factories/`, `abstract_dataset.py`, `model_zoo/`, a Hydra config tree, or a W&B wrapper.

A fixed seed is not enough for reproducibility. Bind split hash, preprocessing version, model and optimizer config, GPU/host, and package versions to the run.

### LLM / Prompt Evaluation

```text
README.md
requirements.txt
run_eval.py
judge.py
prompts/
  system.md
  task.md
data/
  cases.jsonl
runs/
  .gitkeep
docs/
  handoff.md
```

No `src/llmeval/` at the start. The critical part is the run artifact, not code structure, because models and APIs drift:

```text
runs/<run_id>/
  config.json
  raw_outputs.jsonl
  judge_outputs.jsonl
  metrics.json
  report.md
```

Always save raw completions, plus model name, provider, temperature/top_p/max_tokens, system and task prompt hashes, dataset hash, judge model and prompt, and scoring version. Without raw outputs the run cannot be re-scored after a model changes.

### Hardware Capture / Side-Channel

```text
README.md
requirements.txt
Makefile
capture.py
analyze.py
target/
  firmware/
  host/
configs/
  capture.yaml
runs/
  .gitkeep
docs/
  setup.md
  handoff.md
```

Do not solve side-channel rigor with folder count. Expand only when the project grows:

```text
target/   firmware/ host/ disasm/
sca/      capture.py labels.py segment.py leakage.py classify.py plot.py
scripts/  00_smoke.py 10_build_target.sh 20_capture.py 30_analyze.py 40_report.py
configs/  runs/  docs/
```

Use `sca/`, not `src/sca/`. Keep raw traces under the run that produced them, bound to firmware hash, scope config, and trigger strategy, not loose in `data/`.

### Simulation / Theory

```text
README.md
requirements.txt
simulate.py
eval.py
configs/
  base.yaml
runs/
  .gitkeep
docs/
  handoff.md
```

Add `theory.py`, `metrics.py`, or `plot.py` when they are needed. State an evidence tier in results: theory only, synthetic simulation, simulator matched to a reference implementation, measured real data, or independently reproduced. Do not present synthetic success as real-world success.

## Scripts

Create `scripts/` only when three or more distinct stages exist: prepare/run/eval/report are separated, the hardware procedure is staged, or baseline and ablation run through the same stage script. With one or two stages, keep flat scripts (`experiment.py`, `eval.py`).

Use one script per stage, not one per hypothesis. Number with gaps (00, 10, 20) so stages can be inserted later.

Good:

```bash
python scripts/20_run.py --config configs/baseline.yaml
python scripts/20_run.py --config configs/experiment.yaml
python scripts/30_eval.py --run runs/20260616_exp_seed0
```

Avoid per-hypothesis scripts (`20_train_baseline.py`, `21_train_snr.py`, ...) and avoid a mega CLI that hides run order.

## Package Boundary

`scripts/` answers what to run and in what order. Reusable modules answer how the logic works.

Put in `scripts/`: run order, path-only argparse (`--config`, `--run`, `--out`), run naming, and print-based progress. Experiment parameters belong in the YAML config, not in CLI flags.

Put in modules: data loading and preprocessing; model, schedule, policy, or target logic; train/sample/eval loops; metrics; plotting; capture, segmentation, and analysis; small JSON/CSV/NPZ/checkpoint/seed helpers.

Do not put the paper claim, final conclusion, or complete protocol inside one opaque function.

## Configs

Experiment parameters live in the config, never in CLI flags. From Level 1 on, that config is a YAML file under `configs/`; at Level 0 (no `configs/` yet) keep them as named constants at the top of `run.py`. CLI arguments may only reference paths — `--config <yaml>`, `--run <dir>`, `--out <dir>` — never tunable parameters (learning rate, epochs, seed, batch size, model size, thresholds). One readable config should fully describe the run and be recorded with it.

Configs describe experiments; they must not hide them. Prefer explicit, readable YAML. Create `configs/` when there are two or more run conditions or reproducibility matters. Split by role (`data/ model/ train/ exp/`) only after the experiment space grows large. Do not require a config framework at project start.

## Data And Runs

Create `data/` only when real external data exists. Keep `data/raw` (external, unmodified), `data/processed` (derived), and `data/cache` (reproducible temporary state).

Make `runs/` the canonical artifact store and add it early, from Level 1, because binding a result to what produced it is the core job of a research repo. Each run is self-contained:

```text
runs/<timestamp>_<short_name>/
  config.yaml
  manifest.json
  logs/
  metrics/
  plots/
  report.md
```

`manifest.json` records at least run_id, claim, config path, git_commit, seed, data_hash, started_at, finished_at, and status. Add firmware/disasm hashes, device, and scope config for hardware; checkpoint and split hashes for ML. Put checkpoints under the run that produced them, not in a global `models/`.

Start with local files. Add W&B, MLflow, or TensorBoard later as a secondary index; do not remove local `runs/`. Tool-managed directories such as `mlruns/` should usually be Git-ignored while reports and figures stay in `runs/`.

## Docs

Create only the docs that hold current information in the first commit. Do not create empty documentation files.

```text
Level 0:  notes.md
Level 1:  docs/handoff.md   (hypothesis and how-to-run go in README.md)
Level 2:  docs/idea.md, protocol.md, results.md, handoff.md
Level 3:  add docs/archive/ for superseded plans
```

`docs/idea.md` should state the hypothesis, primary metric, secondary metrics, baselines, success criterion, and failure modes. `docs/handoff.md` holds unresolved limitations and next steps; put unfinished work here, not in source comments. Archived notes must say they are not current and point to the current `protocol.md` and `handoff.md`.

## Tests

Tests protect the claim, not coverage. Verify the smallest logic that, if broken, would invalidate a result (labels, splits, metrics, segmentation, statistics).

```text
Level 0:  no tests/ (a small self-check in run.py is enough)
Level 1:  no tests/ by default; add tests/test_smoke.py only if reusable logic exists
Level 2:  tests/test_core.py, test_metrics.py, test_io.py
Level 3:  tests/unit/, smoke/, integration/
```

Separate fast from slow and hardware-dependent checks (`make smoke / test / test-slow / test-hw`). Never put a test that needs hardware in the default `make test`.

## Notebooks

Create `notebooks/` only when notebooks are actually used. They are allowed for inspection, visualization, sample review, dataset checks, and metric debugging, never as the source of truth. Keep train loops, dataset splits, final metrics, and final figures in scripts and modules, regenerable without a notebook.

## Dependency And Build Files

Use one dependency file at a time: `requirements.txt` for Level 0-2, `pyproject.toml` for Level 3. Do not create `requirements.txt`, `pyproject.toml`, `setup.cfg`, and `setup.py` together.

Keep a small `Makefile` as a thin command interface (`smoke`, `run`, `eval`, `report`, `clean`). Experiment logic stays in scripts and configs, not in the Makefile, and the Makefile does not grow one target per hypothesis.

## New Project Procedure

1. State the research question and the claim under test.
2. Pick the lowest level that fits (default Level 1).
3. Choose the domain center.
4. Create only files required for the first run, its reproducibility, and current docs.
5. State, per file, why it is needed now.
6. Make `runs/` the canonical artifact store.
7. Add numbered scripts only when stages appear.
8. Expand to a package or a higher level only on a real trigger.

## Refactoring Procedure

1. Preserve the old state in version control before moving files.
2. Write the current experiment question in one sentence.
3. Identify the correct domain center.
4. Move only files the current question needs.
5. Split mega CLIs into stage scripts.
6. Remove generic config, manifest, schema, registry, and migration machinery first.
7. Move generated artifacts into `runs/`.
8. Keep current idea/protocol/results/handoff at docs root; archive the rest.
9. Keep hardware-free tests for labels, datasets, metrics, segmentation, and statistics.
10. Record limitations in docs, not in stale source comments.

## Avoid

- `src/<package>/`, packages, `data/`, `target/`, `notebooks/`, `tests/unit/`, `docs/archive/`, or config subtrees before the first real experiment needs them;
- generic frameworks, plugin registries, factories, model zoos, or config schema migrations;
- mega CLIs that hide run order;
- experiment parameters exposed as CLI flags instead of living in a YAML config;
- Hydra trees, W&B wrappers, or manifest validators harder than the experiment itself;
- training or final figures that live only in notebooks;
- global checkpoint folders detached from configs and metrics;
- synthetic framework work before real measurement or real training.
