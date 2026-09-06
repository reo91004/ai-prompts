# Evidence Contract

For a claim-bearing experiment, retain:

- The question, claim scope, data provenance, and whether evidence is synthetic, simulated, or measured.
- Seed, configuration, relevant package versions, raw outputs, and the code state needed to reproduce the run.
- The baseline, metric definition, and uncertainty or repetition needed for this conclusion.
- The association between the run and the reported numbers or figures.

Keep the existing field names `evidence_origin` (`synthetic` / `simulated` / `measured`), `evidence_purpose` (`diagnostic` / `claim_bearing`), and `claim_scope`. For measured evidence, `measurement_scope` states what was actually measured. Reuse project identifiers and record a narrowed claim explicitly; do not force cryptographic path categories onto other domains. An isolated component measurement cannot establish whole-system behavior.

The project selects domain checks that protect its actual claim. Hardware checks apply to physical runs; leakage, key-recovery, attack-budget, and trace-alignment evidence apply only to claims that require them.

Use `diagnostic` for debugging or calibration that does not support the reported claim, and `claim_bearing` for evidence used by that claim. Exploratory results may support explicitly scoped observations; selecting a hypothesis on those results does not make them independent confirmation. Preserve original results and distinguish follow-up analysis.

Use existing logs and `.plans/ledger.json` when work needs cross-session recovery. Do not create duplicate packets, hash manifests, or approval records just to restate the evidence.
