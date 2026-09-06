---
name: ai-ml-experiment
description: Use to design or assess AI/ML experiments, evaluation datasets, baselines, metrics, and reproducibility.
---

Apply AI/ML experiment gates. Check dataset version, preprocessing, split logic, sample identity across splits, selection leakage, seeds, hyperparameters, baseline fairness, metric definitions, variance across runs when appropriate, test-set tuning risk, and logs/plots/tables regenerated from source. Classify debugging and calibration outputs as `diagnostic`. Exploratory observations may be `claim_bearing` within an explicitly exploratory scope; selecting a hypothesis or tuning on them does not make them independent confirmation. Confirmatory claims need appropriate independent evaluation, fixed settings, and no test-set tuning. Bind every benchmark claim to the evidence contract and do not claim SOTA, reproduction, or statistically significant improvement beyond that scope.

Use `research-repo-design` when choosing experiment repository structure, not for an ordinary change within an established layout.

Keep the reproducibility gates above in full and implement them with the simplest experiment code that supports the claim. Use the [research code guard policy](../no-placeholder-development/references/research_code_guard_policy.md) when deciding whether a check protects a concrete result or merely repeats another check.

Report the relevant dataset/split, leakage risk, baseline, primary metric, variance plan, test-set tuning risk, evidence purpose/claim scope, and minimum run artifact. Reuse existing run metadata; omit empty headings rather than creating a fixed report for every task.
