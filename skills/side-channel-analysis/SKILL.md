---
name: side-channel-analysis
description: Use for side-channel research, leakage detection, power/EM traces, classifier validation, recovery claims, and countermeasure evaluation.
---

# Side-Channel Analysis

Apply research checks to the actual target, operating conditions, and claim. For meaningful design or interpretation, use the applicable [research principles](../research-domain-router/references/research_principles.md) and only the domain gates the claim needs (for example, hardware, software, AI/ML, or statistics). Side-channel research does not require an LLM or LLM integration.

Record project-specific datasets, target firmware, budgets, venue constraints, and physical-attempt limits in project records, not this skill. This skill guides analysis and evidence; it does not authorize acquisition, hardware operation, exploitation, or key-recovery implementation.

## Evidence gates

- Bind results to the research question, target implementation and binary/firmware/bitstream version, inputs, configuration, seed when applicable, relevant environment versions, raw outputs, and reported metrics or figures. Follow the [evidence contract](../evidence-gate/references/evidence_contract.md).
- State the sampling unit, number of independent units, repeated observations, grouping (such as device, session, key, trace, run, or seed), and split logic. Do not treat windows or resamples from one acquisition as independent traces. Report uncertainty at the level that supports the claim.
- Distinguish synthetic, simulated, and measured evidence; diagnostic and claim-bearing evidence; and measurement scope from claim scope. Separate leakage detection, isolated-primitive or instrumented-subpath results, full-algorithm results, and end-to-end recovery. Measured leakage alone does not establish a full-path or key-recovery claim.
- Check the leakage and adversary models, acquisition and trigger assumptions, trace count, window and alignment, preprocessing, labels and calibration, negative and wrong-window controls, leakage tests, classifier validation, baselines, and claim-relevant ablations. Prevent train/test overlap and device, session, trace, or key leakage when ML is used.
- For physical acquisition, follow [capture integrity](../hardware-capture-integrity/SKILL.md) and the project's safety, equipment, calibration, privacy, retention, and attempt rules. Preserve every physical attempt and raw evidence as required there. For all data, minimize collection, honor authorization and consent, protect secrets and participant or device identifiers, and record access, redaction, retention, and sharing constraints.

## Interpret findings

Lead with the strongest honest result the evidence supports and its conditions, whether favorable or unfavorable. Preserve the original result and distinguish observation, explanation, and untested hypothesis.

For an unexpectedly strong or weak finding, examine plausible explanations across target behavior, code, acquisition, data and labels, preprocessing, splits, metrics, baselines, uncertainty, operating conditions, confounding, and method assumptions. Prioritize discriminating checks that could change the interpretation; label follow-up as exploratory until independently supported. Do not cherry-pick seeds, subsets, windows, metrics, or reruns.

## Return

- Supported result and conditions
- Target and evidence provenance
- Synthetic, simulated, or measured; diagnostic or claim-bearing
- Sampling unit, independence, sample size, splits, and uncertainty
- Controls, baselines, ablations, and validation
- Measurement scope, claim level, and limitations
- Plausible explanations and discriminating checks
- Safety, capture-integrity, privacy, and reproducibility status
