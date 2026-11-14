# Experiment Lifecycle

## Specify

Use one stable experiment ID to connect its card or equivalent specification, code, configuration, attempts, raw outputs, analysis, and judgment. Reuse the repository's naming, output-path helper, and template when present; a supplied example's ID or paths are not defaults.

Before a registered experiment, record:

- Why the experiment matters and which decision it could change.
- Mechanism hypotheses and controls that distinguish them.
- Data provenance, sampling units, training/selection/validation/final-evaluation roles, and applicable public/private definitions.
- Matched comparisons, tuning opportunities, data/acquisition/computation budgets, and shared noise or sampling when relevant.
- Contrasts, metrics and units, uncertainty and multiplicity, and positive/negative/unresolved reading rules.
- Resource limits, missing/duplicate/non-finite input handling, expected artifacts, and resume/attempt rules.

Keep design status (registered, exploratory, post-hoc), evidence origin (analytical, synthetic, simulated, measured), and evidence purpose (diagnostic, claim-bearing) distinct. Reuse local field names. Fix registered criteria before outcomes. An exploratory or anomaly run needs only its question, hypothesis, and the result that would change the next step; record what was observed and what was added afterward.

## Implement And Validate

Reuse existing functions, templates, and analysis paths. Select checks that prevent concrete wrong results: known small inputs, no-signal and positive controls, a synthetic run-to-analysis fixture, rejected missing/duplicate inputs, and a resource pilot when needed. Synthetic fixtures validate the procedure and stay labeled diagnostic. Reuse unaffected checks and reviews.

Fix code, configuration, inputs, environment, and decision rules for the run. Record scientific specification changes; an operational retry is not permission to choose more favorable criteria.

## Execute And Recover

Launch every experiment detached and wait for it as `resource-aware-orchestration/references/experiment_runs.md` describes, so they survive the agent session. Record command and working directory, process/job identity and start time, code/configuration/input versions, persistent logs, output locations, checkpoints, and dependent stages that stop on failure. Use the applicable platform procedure in `resource-aware-orchestration`. An external event file and an event delivered to the active agent are different capabilities.

Do not modify a running experiment's code, support modules, or environment. A wait timeout does not authorize cancellation or duplicate execution. Apply physical acquisition safety on every physical attempt.

Distinguish implementation/input defects, interruption/resource failures, insufficient evidence, and supported negative findings. After a failure, find and fix the cause, then start a new attempt or resume; continue until the experiment answers its question. Record each failed attempt in the card or an `attempts.json` (what ran, configuration, error, observation, fix) and delete its bulky outputs such as traces, checkpoints, and large logs. Keep the outputs of the attempts whose results are reported.

## Verify And Judge

Check terminal exit status, artifact integrity/completeness, and analysis completion. A run.json may be written at startup. A COMPLETED line or accepted submission is a signal to inspect evidence, not a success verdict.

Bind judgment to question/comparison, data scope and selection, seeds, configuration, code/environment/inputs, raw evidence, analysis code, numerical units and uncertainty, permitted claim, and next question. Synthetic checks do not establish real-world utility; measured data alone do not establish independent confirmation. Preserve corrections and abandoned interpretations in the authoritative record.
