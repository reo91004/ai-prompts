# Research Repository Hierarchy

Use this topology when creating or restructuring a research repository. Preserve the parent/child relationships: supplied materials are under docs/, detailed records under records/, executable experiment code under experiments/, and active recovery state under .plans/. For an established repository, map these responsibilities to its actual conventions before changing paths. Create the branches the current work needs.

```text
research-repository/
├── AGENTS.md
├── docs/
│   ├── 00-overview.md
│   ├── 01-timeline.md
│   ├── 02-progress.md
│   ├── idea/
│   ├── lit/
│   ├── ref-code/
│   └── ref-paper/
├── records/
│   ├── conventions.md
│   ├── research-guide.md
│   ├── next-experiments.md
│   ├── claims-evidence.md
│   ├── risks.md
│   ├── glossary.md
│   ├── experiments/
│   │   └── <date>-<id>-<topic>.md
│   ├── rounds/
│   │   └── <discussion-id>/
│   ├── journal/
│   │   └── <date>.md
│   └── archive/
├── experiments/
│   ├── registered/
│   ├── explore/
│   ├── <domain>/
│   ├── lib/
│   └── early/
├── configs/
│   └── <id>_<topic>.json
├── private_work/
│   └── experiments/
│       └── <date>-<id>-<topic>/
│           └── a<N>/
├── results/
├── registry/
├── scripts/
├── tests/
└── .plans/
    ├── HANDOVER.md
    └── ledger.json
```

## Entry And Human-Facing Documents

AGENTS.md links required documents, environments, commands, equipment/resource limits, disclosure rules, and important boundaries. Keep the entry short.

docs/00-overview.md explains the question and why it matters; docs/01-timeline.md gives the scientific chronology; docs/02-progress.md summarizes supported results, open issues, and next experiments. docs/idea/ preserves supplied ideas and proposals. docs/lit/ tracks prior literature, bibliography, source locations, and comparisons. docs/ref-code/ preserves supplied implementations, while docs/ref-paper/ preserves provided manuscripts. A supplied manuscript and our new draft are different artifacts. Ported reference code needs source, revision, license, changes, and validation scope.

## Detailed Research Records

records/conventions.md owns project rules, naming, execution/reporting/commit boundaries, and evidence criteria. records/research-guide.md carries research attitude and anomaly-to-hypothesis-to-experiment guidance. records/next-experiments.md owns next questions and priorities. The project selects one authoritative claim map, such as claims-evidence.md, evidence-map.md, or claims-scope.md; do not create three competing maps. risks.md records concrete scientific/operational risks and glossary.md defines local terminology.

records/experiments/ holds cards linking question, specification, code, configuration, raw outputs, judgment, and corrections. records/rounds/ holds independent prompts, original responses, parent decisions, and adoption reasons. records/journal/ records dated events and links to cards or discussions. records/archive/ preserves earlier systems and completed ledgers without treating them as current state. These are children of records/, not parallel top-level folders.

## Executable Code And Evidence

experiments/registered/ holds code whose criteria were fixed before outcomes. experiments/explore/ holds exploratory, post-hoc, or anomaly analyses. experiments/<domain>/ groups a concrete domain when useful: llm/ is appropriate for real LLM work, sca/ for a side-channel workflow, and neither name establishes evidence grade. experiments/lib/ holds functions, data access, and path helpers shared by actual callers. experiments/early/ preserves earlier implementations needed for history or reproduction. Read [incremental structure guidance](repository-structure.md) before adding packaging or workflow machinery.

configs/ holds execution/evaluation settings worth separating from code. private_work/ holds untracked raw inputs, subject-level output, models, logs, and large artifacts under local retention and access rules. private_work/experiments/<experiment>/a<N>/ separates execution attempts. results/ holds only shareable aggregates, tables, and figures permitted by the repository, linked to generation code. A private_work directory name does not determine statistical public/private roles or a DP guarantee.

registry/ contains derived experiment/discussion/output indexes and path mappings. Generate it from authoritative records; do not maintain it as another manual source of truth. scripts/ contains repository-wide indexing, search, execution-status, or event tools. tests/ checks real structure, paths, input contracts, and analysis behavior.

## One Experiment Across The Depths

```text
records/experiments/2026-11-03-x154m-gradient-difference-reuse.md
experiments/explore/x154m_gradient_difference.py
configs/x154m_gradient_difference.json
private_work/experiments/2026-11-03-x154m-gradient-difference-reuse/a3/
```

This supplied example illustrates the connection, not a universal ID or DP experiment requirement. The date is the first-record date; the stable ID links card, code, config, and outputs; the topic describes the question; a<N> identifies an execution attempt. In this naming convention, executable filenames omit the date because the card owns chronology. Use the current project's output helper, such as experiments.lib.paths.out_dir when it exists, to maintain the card-to-output relationship. Reuse another established naming convention rather than imposing this example on existing work.

## Active Recovery State And Units

.plans/HANDOVER.md records what is running and the next safe waiting/resume action. .plans/ledger.json points to active work, user constraints, deadlines, next action, and authoritative records. .plans/ is current recovery state; records/ is detailed research history. If the project already has equivalent paths, preserve them.

An experiment has one question/method/comparison/evaluation scope. An attempt is an operational execution or recovery instance and can contain several seeds or stages. A seed is a random realization, not automatically a new subject/device/acquisition. A stage is preparation, capture, training, analysis, or figure generation. A judgment states supported, contradicted, or unresolved findings. A handover preserves continuity without declaring the research complete.

Local disclosure thresholds, PDF caches, device names, datasets, Python/GPU settings, and registry commands come from repository instructions. The supplied dp example's aggregation threshold is not a global rule.
