# Research Experiment Repository Design

Use this reference when a repository exists to test a research idea through experiments, measurements, model training, simulation, hardware runs, or side-channel traces. The goal is not to build a reusable framework first. The goal is to make the experiment easy to run, audit, reproduce, compare, and hand off.

## Core Principle

Keep the philosophy stable, but choose the center of the repository from the domain:

- `scripts/` shows the experiment protocol.
- `<pkg>/` provides reusable research parts.
- `configs/` records experiment conditions.
- `runs/` stores all outputs from a concrete run.
- `docs/` stores hypotheses, protocol, interpretation, and handoff.
- `tests/` protects small reusable logic.

Hardware and side-channel repositories usually center on `target/`. AI and ML repositories usually center on `data/`, model/training/sampling/evaluation code, and `runs/`. Simulation repositories usually center on simulation inputs, simulators, and evaluators.

Prefer visible, slightly duplicated experiment scripts over hidden mega CLIs, plugin systems, or generic frameworks.

## Choose The Center

Use this mapping before choosing a top-level layout:

```text
Hardware / side-channel:
  center: target/, scripts/, runs/
  package: targetref.py, device.py, scope.py, capture.py, labels.py, segment.py, analyze.py

AI / diffusion / ML:
  center: data/, model/training/sampling/evaluation, runs/
  package: data.py, model.py, train.py, sample.py, eval.py, metrics.py, plot.py

LLM fine-tuning:
  center: data/, tokenizer/model/training/generation/evaluation, runs/
  package: data.py, tokenizer.py, model.py, train.py, generate.py, eval.py, metrics.py

RL:
  center: envs, rollout, policy/training/evaluation, runs/
  package: envs.py, policy.py, rollout.py, train.py, eval.py, metrics.py

Simulation / theory experiments:
  center: simulate/evaluate/report, runs/
  package: simulate.py, eval.py, metrics.py, plot.py
```

Do not copy a hardware layout into an AI project just because it worked for a hardware paper. Keep the roles and change the folders.

## Level 1: Minimal Hypothesis Repository

Use this when one researcher needs to test a small idea quickly.

```text
<project>/
  README.md
  Makefile
  requirements.txt

  <pkg>/
    data.py
    model.py
    train.py
    eval.py
    util.py

  scripts/
    00_smoke.py
    20_train.py
    40_eval.py

  configs/
    base.yaml
    exp.yaml

  runs/
    .gitkeep

  docs/
    idea.md
    handoff.md

  tests/
    unit/
```

## Level 2: Paper Experiment Repository

Use this as the default for paper-level experiments, including AI/ML, hardware, side-channel, cryptography, and simulation work.

```text
<project>/
  README.md
  Makefile
  pyproject.toml
  requirements.txt
  .gitignore

  <pkg>/
    data.py
    model.py
    train.py
    sample.py
    eval.py
    metrics.py
    plot.py
    util.py

  scripts/
    00_smoke.py
    10_prepare_data.py
    20_train.py
    30_sample.py
    40_eval.py
    50_report.py

  configs/
    base.yaml
    exp_baseline.yaml
    exp_hypothesis.yaml
    exp_ablation.yaml

  data/
    raw/
    processed/
    cache/

  runs/
    .gitkeep

  docs/
    idea.md
    protocol.md
    results.md
    handoff.md

  notebooks/
    .gitkeep

  tests/
    unit/
```

For hardware and side-channel projects, add `target/` and replace package modules with target-aware pieces such as `targetref.py`, `device.py`, `scope.py`, `capture.py`, `labels.py`, and `segment.py`. For AI projects, `target/` is usually absent.

## Level 3: Larger ML System Repository

Use this only when the project has many datasets, models, trainers, evaluators, and collaborators.

```text
<project>/
  README.md
  Makefile
  pyproject.toml

  <pkg>/
    data/
    models/
    training/
    sampling/
    evaluation/
    callbacks/
    utils/

  scripts/
    train.py
    sample.py
    evaluate.py
    report.py

  configs/
    data/
    model/
    train/
    exp/

  data/
  runs/
  notebooks/
  docs/
  tests/
```

Do not start at Level 3 unless the complexity already exists.

## Scripts

Use one script per experiment stage, not one script per hypothesis.

Good:

```bash
python scripts/20_train.py --config configs/exp_baseline.yaml
python scripts/20_train.py --config configs/exp_hypothesis.yaml
python scripts/40_eval.py --run runs/20260610_exp_seed0
```

Avoid:

```text
20_train_baseline.py
21_train_snr.py
22_train_vpred.py
23_train_aug.py
```

Hardware modes may deserve separate scripts when the physical procedure differs. AI experiments usually differ by config, so keep the stage script stable.

## Package Boundary

`scripts/` answers what to run and in what order. `<pkg>/` answers how the reusable logic works.

Put in `scripts/`:

- run order;
- hardware or training execution order;
- `argparse`;
- run naming;
- config selection;
- high-level mode selection;
- print-based progress logs.

Put in `<pkg>/`:

- data loading and preprocessing;
- model, schedule, policy, or target reference logic;
- train/sample/eval loops;
- metrics;
- plotting;
- capture, segmentation, and analysis helpers;
- small JSON, CSV, NPZ, checkpoint, and seed utilities.

Do not put the paper claim, final conclusion, or complete protocol inside one opaque package function.

## Configs

Configs describe experiments. They must not hide experiments.

For small projects, prefer explicit files:

```text
configs/
  base.yaml
  exp_baseline.yaml
  exp_hypothesis.yaml
```

For AI projects that grow beyond roughly 20 experiments, split by role:

```text
configs/
  data/
  model/
  train/
  exp/
```

Hydra-style composition can be useful after the experiment space becomes large, but do not require it at project start. A simple YAML file that is easy to read is better than a config framework that obscures the run.

## Data And Runs

For AI/ML, keep `data/` and `runs/` separate:

```text
data/
  raw/
  processed/
  cache/
```

`data/raw` is external input and should not be manually modified. `data/processed` is derived data. `data/cache` is reproducible temporary state.

Put checkpoints under the run that produced them:

```text
runs/<run>/
  config.yaml
  meta.json
  logs/
    train.csv
    val.csv
  ckpt/
    last.pt
    best.pt
  samples/
  metrics/
    fid.json
  plots/
    loss.png
    sample_grid.png
  report.md
```

Avoid a global `models/` directory for checkpoints unless the project is explicitly a model registry. Research checkpoints need their config, seed, logs, samples, metrics, and report nearby.

## Notebooks

Notebooks are allowed for inspection, visualization, sample review, dataset checks, and metric debugging. They must not be the source of truth.

Keep this boundary:

- experiment execution: `scripts/`;
- reusable logic: `<pkg>/`;
- final figures and reports: `scripts/50_report.py` or `<pkg>/plot.py`;
- exploration and inspection: `notebooks/`.

Do not leave train loops, dataset splits, final metrics, or only-copy figures inside notebooks.

## Tracking Tools

Start with local files:

```text
runs/<run>/config.yaml
runs/<run>/logs/train.csv
runs/<run>/metrics/*.json
runs/<run>/report.md
```

If the project grows, add W&B, MLflow, TensorBoard, or another tracker as a secondary index. Do not remove local `runs/`. Tool-managed directories such as `mlruns/` should usually be ignored by Git, while important reports and figures remain in `runs/`.

## Docs

Every research repository should have a small current source of truth:

```text
docs/
  idea.md
  protocol.md
  results.md
  handoff.md
```

`docs/idea.md` should include:

```markdown
# Idea

## Hypothesis
[What should improve, and why?]

## Primary Metric
[The metric that decides success.]

## Secondary Metrics
[Metrics that catch regressions or side effects.]

## Baselines
[The fair comparisons.]

## Success Criterion
[What result counts as success? Include seeds or variance when relevant.]

## Failure Modes
[How the result could be misleading.]
```

Move old plans to `docs/archive/` or delete them. Archived notes must say they are not current and point to current `docs/protocol.md` and `docs/handoff.md`.

## New Project Procedure

1. State the research question and claim under test.
2. Choose the center: hardware target, AI data/model/training, RL environment, or simulation.
3. Choose Level 1, Level 2, or Level 3.
4. Create numbered scripts for stages, not hypotheses.
5. Put reusable logic in a short root package.
6. Add configs that a researcher can read without a framework.
7. Make `runs/` the canonical artifact store.
8. Write `docs/idea.md` and `docs/protocol.md` before expanding.
9. Add small tests for reusable logic.
10. Add heavier tools only after the simple structure is insufficient.

## Refactoring Procedure

1. Preserve the old state in version control before moving files.
2. Write the current experiment question in one sentence.
3. Identify the correct center for the domain.
4. Move only files directly needed by the current question.
5. Split giant CLIs into stage scripts.
6. Remove generic config, manifest, schema, registry, and migration machinery first.
7. Move generated artifacts into `runs/`.
8. Keep current protocol, results, and handoff documents at docs root.
9. Keep hardware-free tests for labels, datasets, metrics, segmentation, and statistics.
10. Record limitations and missing evidence in docs, not stale source comments.

## Avoid

- generic frameworks before the experiment needs them;
- plugin registries for one or two backends;
- config schema migrations before stable configs exist;
- manifest validators that are harder than the experiment;
- mega CLIs that hide run order;
- training only from notebooks;
- global checkpoint folders detached from configs and metrics;
- synthetic framework work before real measurement or real training.
