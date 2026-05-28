# Evidence and Acceptance Gate

Accept only if all relevant items hold:
1. The research question or development goal is explicit.
2. The artifact scope is known.
3. Required deterministic checks were run or explicitly marked unavailable.
4. Logs, data, code, derivations, citations, or reports support the claim.
5. Adversarial review was performed for important changes.
6. No placeholder, fake-pass, TODO, dummy, stub, or test-only hardcoding remains.
7. Reproducibility path exists when required.
8. Limitations are documented.
9. Claims do not exceed evidence.

Block if logs are missing, results are partial but described as complete, review is generic, daemon restart is used as evidence, tests pass only because behavior was bypassed, data or plots cannot be regenerated, or the claim relies on hidden assumptions.
