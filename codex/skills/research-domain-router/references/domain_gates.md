# Universal Domain Gates

## Development Gate
Use for production code, scripts, APIs, CLIs, tools, automation, refactors, debugging, and CI. Required evidence may include tests, lint, type checks, build logs, integration checks, and code review.

## AI / ML Gate
Use for training, evaluation, model comparison, prompts, datasets, embeddings, finetuning, and benchmarks. Require dataset version, splits, seeds, hyperparameters, metrics, baselines, logs, variance when appropriate, and no test-set tuning.

## Side-Channel Gate
Use for leakage detection, trace analysis, classifier training, key recovery, attack simulation, measurement, and countermeasure evaluation. Require target implementation/binary or bitstream, leakage model, trace setup, labels, negative controls, wrong-window controls, classifier validation, ablations, and clear separation between synthetic and real evidence.

## Crypto / Security Gate
Use for cryptographic protocols, attacks, threat models, implementation security, and countermeasures. Require adversary model, public/secret variables, assumptions, security objective, attack success criterion, and limitation disclosure.

## Hardware / Vivado Gate
Use for FPGA, RTL, synthesis, implementation, timing, utilization, simulation, constraints, and bitstream-related claims. Require tool version, target part, constraints, logs, simulation evidence, synthesis/implementation reports, timing/utilization reports when claiming timing or area.

## Research Experiment Repo Gate
Use for creating, reviewing, or refactoring repositories whose purpose is to validate a paper idea through experiments, model training, measurements, simulations, hardware runs, side-channel traces, or FPGA/embedded targets. Require a clear research question, chosen domain center, explicit script/package boundary, config policy, current docs source of truth, run artifact policy, hardware-free tests for reusable logic, and no premature generic framework.

For research code, require guards that protect claim integrity: provenance, seed/config/run binding, artifact existence, synthetic/measured separation, and claim scope. Treat production-only defensive programming as optional unless production behavior is part of the claim.

## Statistics Gate
Use for statistical claims, significance, uncertainty, robustness, ablations, and sample-based conclusions. Require sample size, variance/CI when appropriate, multiple-run reporting, and no cherry-picking.

## Writing Gate
Use for papers, reports, READMEs, rebuttals, and documentation. Require claims to match evidence, limitations to be explicit, tables/figures traceable to source data, and citations to support the attached claims.
