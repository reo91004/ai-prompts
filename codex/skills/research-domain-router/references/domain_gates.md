# Universal Domain Gates

## How To Read A Gate

A gate lists the evidence a **finished claim** must carry. It is not a specification for code to write now. Items are tagged:

- `[code]` — must exist in the script before the first real run;
- `[run]` — evidence produced by actually running the experiment.

Never build a module, runner, or scaffold for a `[run]` item ahead of time. Negative controls, ablations, and variance are experiments to perform, not subsystems to design. Write the `[code]` items, run the experiment, and add each `[run]` artifact when the run that produces it exists.

When several gates apply to one task, they do not multiply the code — they share one script. Satisfy the strictest `[code]` item and stop.

## Development Gate
Use for production code, scripts, APIs, CLIs, tools, automation, refactors, debugging, and CI. Required evidence may include tests, lint, type checks, build logs, integration checks, and code review. `[run]`

## AI / ML Gate
Use for training, evaluation, model comparison, prompts, datasets, embeddings, finetuning, and benchmarks. Require dataset version, splits, seeds, and hyperparameters `[code]`; metrics, baselines, logs, variance when appropriate, and no test-set tuning `[run]`.

## Side-Channel Gate
Use for leakage detection, trace analysis, classifier training, key recovery, attack simulation, measurement, and countermeasure evaluation. Require the target implementation/binary or bitstream, leakage model, trace setup, labels, and clear separation between synthetic and real evidence `[code]`; negative controls, wrong-window controls, classifier validation, and ablations `[run]`.

## Crypto / Security Gate
Use for cryptographic protocols, attacks, threat models, implementation security, and countermeasures. Require adversary model, public/secret variables, assumptions, security objective, attack success criterion, and limitation disclosure. `[run]`

## Hardware / Vivado Gate
Use for FPGA, RTL, synthesis, implementation, timing, utilization, simulation, constraints, and bitstream-related claims. Require tool version, target part, and constraints `[code]`; logs, simulation evidence, synthesis/implementation reports, and timing/utilization reports when claiming timing or area `[run]`.

## Research Experiment Repo Gate
Use for creating, reviewing, or refactoring repositories whose purpose is to validate a paper idea through experiments, model training, measurements, simulations, hardware runs, side-channel traces, or FPGA/embedded targets. Require a clear research question, chosen domain center, explicit script/package boundary, config policy, current docs source of truth, run artifact policy, hardware-free tests for reusable logic, and no premature generic framework. `[code]`

For research code, require guards that protect claim integrity: provenance, seed/config/run binding, artifact existence, synthetic/measured separation, and claim scope. Delete production-only defensive programming rather than deferring it; see `no-placeholder-development/references/research_code_guard_policy.md`.

## Statistics Gate
Use for statistical claims, significance, uncertainty, robustness, ablations, and sample-based conclusions. Require sample size, variance/CI when appropriate, multiple-run reporting, and no cherry-picking. `[run]`

## Writing Gate
Use for papers, reports, READMEs, rebuttals, and documentation. Require claims to match evidence, limitations to be explicit, tables/figures traceable to source data, and citations to support the attached claims. `[run]`
