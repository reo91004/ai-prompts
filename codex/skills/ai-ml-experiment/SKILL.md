---
name: ai-ml-experiment
description: Use for AI/ML experiments, model evaluation, datasets, prompts, baselines, metrics, and reproducibility.
---

Apply AI/ML experiment gates. Check dataset version, preprocessing, split logic, sample identity across splits, selection leakage, seeds, hyperparameters, baseline fairness, metric definitions, variance across runs when appropriate, test-set tuning risk, and logs/plots/tables regenerated from source. Classify debugging and calibration outputs as `diagnostic`. Exploratory observations may be `claim_bearing` within an explicitly exploratory scope; selecting a hypothesis or tuning on them does not make them independent confirmation. Confirmatory claims need appropriate independent evaluation, fixed settings, and no test-set tuning. Bind every benchmark claim to the evidence contract and do not claim SOTA, reproduction, or statistically significant improvement beyond that scope.

When creating or refactoring an AI/ML research repository, also use `research-repo-design` before accepting the structure.

Keep the reproducibility gates above in full, but implement them as the simplest experiment code that supports the claim — no production-style defensive layers, duplicated checks, or framework machinery (`no-placeholder-development/references/research_code_guard_policy.md`).

## Output
- Dataset:
- Split:
- Leakage risk:
- Baseline:
- Primary metric:
- Variance plan:
- Test-set tuning risk:
- Evidence purpose and claim scope:
- Minimum run artifact:
