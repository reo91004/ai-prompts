---
name: research-repo-design
description: Use when creating, reviewing, or refactoring research experiment repositories across AI/ML, hardware, side-channel, simulation, and paper-idea validation work.
---

## Use
Apply this skill before designing a new research repository, reorganizing an experimental repo, or acting on a handoff that changes repo structure.

Use it for AI/ML, diffusion, LLM fine-tuning, RL, hardware measurement, side-channel, crypto, FPGA, embedded, simulation, and other paper-idea validation projects where the repository is an experiment vehicle rather than a reusable library.

Read `references/research_experiment_repo.md` before proposing or accepting a repository structure. Follow its Minimal Creation Rule: create only files needed for the first run, its reproducibility, or current docs.

Apply the Global Core → Domain Skill → Project Overlay hierarchy. Do not require `.omo`, fixed experiment stages, equipment constants, resource policy frameworks, or review-policy frameworks in every research repository. Put repository-specific values in the Project Overlay and invoke the shared skills on demand.

## Default
When asked to create an initial research repository, default to Level 1 unless the user asks for paper-artifact quality or the first run needs hardware, real data, or model-training stages. Ask at most one question when the domain is unclear; otherwise create the smallest runnable skeleton.

## Output
Return:

1. Selected level (0/1/2/3) and the chosen domain center.
2. Why not a higher level.
3. Files to create now, each with a one-line reason.
4. Files not to create yet.
5. First run command.
6. First evidence artifact (what `runs/<id>/` will hold).
7. Expansion trigger (what must happen before adding a package, `scripts/`, `data/`, or a higher level).
