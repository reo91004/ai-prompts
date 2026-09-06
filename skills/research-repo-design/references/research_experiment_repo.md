# Research Experiment Repository

Structure follows current experiments and real reuse.

- Start with a directly runnable script and the data/output locations it needs. Record the command, seed, configuration, and environment needed to reproduce the result.
- Extract functions for clarity; extract shared modules when a second real caller needs them.
- Use an installable package only when imports or multiple entry points need it. If chosen, prefer an ordinary `src/<package>/` layout and an appropriate `pyproject.toml`; avoid manual `sys.path` changes.
- Add `configs/` when external configuration is useful, `scripts/` when entry points need organizing, and a Makefile when recurring commands benefit from one. None is a prerequisite for a small experiment.
- Preserve raw input and output, distinguish derived artifacts, and bind each run to its seed, parameters, relevant versions, and code state. Paths may be simple; traceability must be real.
- Isolate hardware capture, offline analysis, and simulation when mixing them could confuse evidence or equipment use.
- Exclude large/private raw data and regenerable output from Git as appropriate, while retaining the configuration and evidence pointers needed for recovery.

Review only the structure needed by the current task. Fixed stage names, schemas, and directories belong in a project overlay when that project actually needs them.

## Evidence That Structure Must Preserve

- ML: retain dataset version/identity, split membership, preprocessing, model/optimizer settings, seed, relevant host/GPU context, and package versions with the run.
- LLM evaluation: retain raw completions, model/provider, generation settings, actual prompts, dataset identity, judge model/prompt, and scoring version so the run can be rescored. Identify mutable inputs by a saved copy, version, or hash as appropriate; this is input identity, not an artifact-sealing system.
- Hardware: physical runs follow [capture integrity](../../hardware-capture-integrity/SKILL.md) and the applicable project output profile; simplifying layout does not weaken capture safety or raw evidence requirements.
- Simulation: label the evidence tier and comparison target; do not present synthetic success as measured success.
- Check the smallest logic whose error could invalidate the result, such as labels, splits, metrics, segmentation, and statistics. Keep hardware-dependent checks out of the default offline test command.
- Final metrics and figures must be regenerable from source data and recorded settings. A notebook may support exploration; preserve a repeatable execution path for reported results.

Use one dependency definition appropriate to the existing project. Do not add or remove packaging tools or lockfiles merely to enforce a universal convention; preserve the environment information that reproduction actually needs.
