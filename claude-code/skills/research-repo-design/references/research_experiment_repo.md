# Research Experiment Repository Design

Use this reference when a repository exists to test a research idea through experiments, measurements, model training, simulation, hardware runs, or side-channel traces. The goal is not to build a reusable framework first. The goal is to make the first real experiment easy to run, audit, reproduce, compare, and hand off.

A research repository proves a claim; it is not a product. It may grow large, but each added file must protect claim validity, reproducibility, or provenance. If a file only makes the work feel more like production, do not create it.

## The Layout

One layout, always the same, so a path never has to be guessed — by the author or by an agent reading the repo cold.

```text
README.md               # the hypothesis and how to run it
pyproject.toml
Makefile                # setup / smoke / run / eval / report / clean
<project>/              # shallow root package, snake_case of the repo name
  __init__.py
  core.py               # split into data.py / model.py / metrics.py / plot.py as it grows
scripts/
  00_smoke.py 10_prepare.py 20_run.py 30_eval.py 40_report.py
configs/
  base.yaml baseline.yaml experiment.yaml
runs/                   # canonical artifact store, never hand-edited
docs/
  idea.md protocol.md results.md handoff.md
tests/
  test_core.py
```

**Creation rule: directories always exist; a file appears when it has content.** `docs/` is there from the first commit, `docs/results.md` arrives when there is a result. Never scaffold an empty file to fill the shape.

`make setup` must run the editable install (`pip install -e .`). It is the one line that keeps the package from turning into a `ModuleNotFoundError` in a fresh environment, so it is not optional.

The package sits at the repository root, never at `src/<package>/`. Root-level modules would be simpler still, but a package prevents a file like `types.py` or `random.py` from shadowing the standard library, and that failure is hard to diagnose. One level of depth buys that; two do not.

### Domain Addition

Add at most one domain directory to the layout above. Nothing else changes.

```text
Hardware / side-channel:  target/firmware/, target/host/
AI / ML:                  data/            (only once real external data exists)
LLM / prompt evaluation:  prompts/, data/cases.jsonl
Simulation / theory:      nothing
```

For hardware work, `runs/` follows the capture run directory contract in `hardware-capture-integrity/references/capture_run_layout.md`, which is stricter than the general shape below.

## Choose The Center

The layout is fixed; what fills the package is not. Name the center from the domain:

```text
Hardware / side-channel:  capture + analyze, target/, runs/
AI / ML:                  train + eval, data (when real), runs/
LLM / prompt evaluation:  run_eval + judge, prompts/, runs/ (save raw outputs)
RL:                       envs, policy + rollout, train + eval, runs/
Simulation / theory:      simulate + eval, runs/
```

Do not copy a hardware center into an AI project because it worked for a hardware paper.

### Do Not Create These

Per domain, these are the shapes that show up uninvited and never earn their place at the start:

- **AI / ML**: `callbacks/`, `trainers/`, `registries/`, `factories/`, `abstract_dataset.py`, `model_zoo/`, a Hydra config tree, or a W&B wrapper. A fixed seed is not enough for reproducibility — bind split hash, preprocessing version, model and optimizer config, GPU/host, and package versions to the run.
- **LLM / prompt evaluation**: any structure that matters more than the run artifact. Models and APIs drift, so always save raw completions plus model name, provider, temperature/top_p/max_tokens, system and task prompt hashes, dataset hash, judge model and prompt, and scoring version. Without raw outputs the run cannot be re-scored after a model changes.
- **Simulation / theory**: a solver abstraction before the second solver. State an evidence tier in results — theory only, synthetic simulation, simulator matched to a reference implementation, measured real data, or independently reproduced. Never present synthetic success as real-world success.

## Scripts

Use one script per stage, not one per hypothesis. Number with gaps (00, 10, 20) so stages can be inserted later. With only one or two stages, a single `scripts/20_run.py` is the whole of `scripts/`.

```bash
python scripts/20_run.py --config configs/baseline.yaml
python scripts/20_run.py --config configs/experiment.yaml
python scripts/30_eval.py --run runs/20260616_exp_seed0
```

Avoid per-hypothesis scripts (`20_train_baseline.py`, `21_train_snr.py`, …) and avoid a mega CLI that hides run order.

## Package Boundary

`scripts/` answers what to run and in what order. The package answers how the logic works.

Put in `scripts/`: run order, path-only argparse (`--config`, `--run`, `--out`), run naming, and print-based progress. Experiment parameters belong in the YAML config, not in CLI flags.

Put in the package: data loading and preprocessing; model, schedule, policy, or target logic; train/sample/eval loops; metrics; plotting; capture, segmentation, and analysis; small JSON/CSV/NPZ/checkpoint/seed helpers.

Do not put the paper claim, final conclusion, or complete protocol inside one opaque function.

## Configs

Experiment parameters live in `configs/*.yaml`, never in CLI flags. CLI arguments may only reference paths — `--config <yaml>`, `--run <dir>`, `--out <dir>` — never tunable parameters (learning rate, epochs, seed, batch size, model size, thresholds). One readable config should fully describe the run and be recorded with it.

Configs describe experiments; they must not hide them. Prefer explicit, readable YAML. Split by role (`data/ model/ train/ exp/`) only after the experiment space grows large. Do not adopt a config framework.

## Data And Runs

`data/` appears only when real external data exists. Keep `data/raw` (external, unmodified), `data/processed` (derived), and `data/cache` (reproducible temporary state).

`runs/` is the canonical artifact store and exists from the first commit, because binding a result to what produced it is the core job of a research repo. Each run is self-contained:

```text
runs/<timestamp>_<short_name>/
  config.yaml
  manifest.json
  logs/
  metrics/
  plots/
  report.md
```

`manifest.json` records at least run_id, claim, config path, git_commit, seed, started_at, finished_at, and status. Hash the run's *inputs* when they can change silently — dataset, firmware, prepared queries — and add device and scope config for hardware, checkpoint and split hashes for ML. Do not hash the artifacts the run just wrote; `git_commit` identifies the code and the copied `config.yaml` identifies the settings. Put checkpoints under the run that produced them, not in a global `models/`.

Start with local files. Add W&B, MLflow, or TensorBoard later as a secondary index; do not remove local `runs/`. Tool-managed directories such as `mlruns/` should usually be Git-ignored while reports and figures stay in `runs/`.

## Docs

`docs/` exists from the start; each file appears when it holds current information. Never create an empty documentation file.

`docs/idea.md` states the hypothesis, primary metric, secondary metrics, baselines, success criterion, and failure modes. `docs/protocol.md` is how the experiment is actually run. `docs/results.md` is the canonical home of a measured value. `docs/handoff.md` holds unresolved limitations and next steps — unfinished work goes here, not in source comments.

Add `docs/archive/` only when a plan is superseded. Archived notes must say they are not current and point to the current `protocol.md` and `handoff.md`.

## Tests

Tests protect the claim, not coverage. Verify the smallest logic that, if broken, would invalidate a result: labels, splits, metrics, segmentation, statistics.

Start with `tests/test_core.py` and split into `test_metrics.py`, `test_io.py` when it grows. Separate fast from slow and hardware-dependent checks (`make smoke / test / test-slow / test-hw`). Never put a test that needs hardware in the default `make test`.

## Notebooks

Create `notebooks/` only when notebooks are actually used. They are allowed for inspection, visualization, sample review, dataset checks, and metric debugging, never as the source of truth. Keep train loops, dataset splits, final metrics, and final figures in scripts and the package, regenerable without a notebook.

## Dependency And Build Files

Use `pyproject.toml` alone, with plain `pip` and `venv`. Do not create `requirements.txt`, `setup.cfg`, or `setup.py` alongside it. Its `dependencies` list is the dependency file — that is why there is no second one.

Keep it minimal. This is the whole file for most research repos:

```toml
[project]
name = "myproject"
version = "0"
dependencies = ["numpy", "scipy"]

[build-system]
requires = ["setuptools"]
build-backend = "setuptools.build_meta"
```

Do not introduce `uv`, Poetry, PDM, Pipenv, or Conda as required tooling, and do not generate a lockfile (`uv.lock`, `poetry.lock`, `requirements.lock`, pip-compile output, `--require-hashes`). A lockfile pins a whole dependency graph to defend a deployment against drift between machines and over time; a single-author experiment repo has neither problem, and the file is large, unreadable, and regenerated by a tool the reader may not have installed. When a specific version actually affects a result, pin that one package in `dependencies` (`numpy==2.1.3`) and say why in `README.md`. Record the versions that produced a number in the run manifest, not in a lockfile.

Keep a small `Makefile` as a thin command interface (`setup`, `smoke`, `run`, `eval`, `report`, `clean`). Experiment logic stays in scripts and configs, not in the Makefile, and the Makefile does not grow one target per hypothesis.

## New Project Procedure

1. State the research question and the claim under test.
2. Choose the domain center and its one domain directory, if any.
3. Create the layout's directories, plus only the files the first run and its current docs actually need.
4. State, per file, why it is needed now.
5. Make `make setup` and `make smoke` work before anything else.
6. Add stage scripts as stages appear; keep `runs/` the canonical artifact store.

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

- `src/<package>/`, nested subpackages, `data/`, `target/`, `notebooks/`, `tests/unit/`, `docs/archive/`, or config subtrees before the work needs them;
- generic frameworks, plugin registries, factories, model zoos, or config schema migrations;
- mega CLIs that hide run order;
- experiment parameters exposed as CLI flags instead of living in a YAML config;
- Hydra trees, W&B wrappers, or manifest validators harder than the experiment itself;
- `uv`, Poetry, PDM, Pipenv, or Conda as required tooling, and any lockfile or hash-pinned requirements file — plain `pip` with `pyproject.toml` is the whole dependency story;
- training or final figures that live only in notebooks;
- global checkpoint folders detached from configs and metrics;
- synthetic framework work before real measurement or real training.
