# Research Repository Hierarchy

Follow this layout exactly in research repositories: supplied materials under docs/, detailed records under records/, executable experiment code under experiments/, and active recovery state under .plans/. Create the branches the current work needs; do not add parallel top-level folders or another record system. When a project AGENTS.md maps a responsibility to an existing path, use that path.

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
│   ├── ref-paper/
│   ├── paper/                    # Overleaf project root: LaTeX inputs only
│   │   ├── main<K>_v<N>.tex      # every version of the current series
│   │   ├── figures/              # live figure pool; v<N>/ keeps figures an older version reads
│   │   ├── main<K-1>/            # previous series, self-contained
│   │   └── submissions/<venue>/  # each submitted paper, self-contained and frozen
│   ├── paper-pdf/                # rendered PDFs at the same relative paths (untracked)
│   └── venues/
│       └── <venue>/              # README.md, planning/, record/, rebuttal/
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

docs/00-overview.md explains the question and why it matters; docs/01-timeline.md gives the scientific chronology; docs/02-progress.md summarizes supported results, open issues, and next experiments. docs/idea/ preserves supplied ideas and proposals. docs/lit/ is where agents organize the literature: bibliography, paper notes, source locations, and comparisons. docs/ref-code/ and docs/ref-paper/ hold code and papers supplied by the user or the professor; agents read them but never add, edit, move, or delete files there. Code ported from ref-code/ lives under experiments/ with its source, revision, license, changes, and validation scope noted. A supplied manuscript and our new draft are different artifacts.

## Manuscripts And Venue Documents

docs/paper/ is the supervisor's Overleaf project root: uploading it as is must render every manuscript in it. It holds only what LaTeX reads: sources, bibliographies, class/style/bst files, venue templates, and figures. Nothing else goes there, because Overleaf shows the supervisor every file in the tree. Rendered PDFs go to docs/paper-pdf/ at the same relative path (docs/paper/submissions/<venue>/main.tex renders to docs/paper-pdf/submissions/<venue>/main.pdf); they are rebuilt from source and stay untracked. Agent rules and README notes about the manuscripts go in the project AGENTS.md manuscript section. Figure data, number tables, and provenance stay with the generating code's outputs in results/ or the tracked evidence path named in AGENTS.md, so figures/ holds only the figure files. Build logs and auxiliary files never land in docs/paper/; render into a temporary directory.

docs/venues/<venue>/ holds documents for one submission cycle and no code: README.md (venue, deadlines, page limits, status), planning/ (plans and the carry-over from an earlier cycle), record/ (README.md as the current evidence record, plus the PDF actually submitted, frozen), and rebuttal/ (reviews/ verbatim, numbered analyses, drafts/). Rebuttal experiments are ordinary experiment cards, code, and configs under the usual paths; do not create venue-named experiment or config folders. [Manuscript workspace](../../paper-writing/references/manuscript_workspace.md) gives the version, submission, review, and upload procedures.

## Detailed Research Records

records/conventions.md owns project rules, naming, execution/reporting/commit boundaries, and evidence criteria. records/research-guide.md carries research attitude and anomaly-to-hypothesis-to-experiment guidance. records/next-experiments.md owns next questions and priorities. The project selects one authoritative claim map, such as claims-evidence.md, evidence-map.md, or claims-scope.md; do not create three competing maps. risks.md records concrete scientific/operational risks and glossary.md defines local terminology.

records/experiments/ holds cards linking question, specification, code, configuration, raw outputs, judgment, and corrections. records/rounds/<date>-<id>-<topic>/ holds one discussion round as Markdown: question.md, codex.md, claude.md, an optional second exchange, and decision.md. records/journal/ records dated events and links to cards or discussions. records/archive/ preserves earlier systems and completed ledgers without treating them as current state. These are children of records/, not parallel top-level folders.

## Executable Code And Evidence

experiments/registered/ holds code whose criteria were fixed before outcomes. experiments/explore/ holds exploratory, post-hoc, or anomaly analyses. experiments/<domain>/ groups a concrete domain when useful: llm/ is appropriate for real LLM work, sca/ for a side-channel workflow, and neither name establishes evidence grade. experiments/lib/ holds functions, data access, and path helpers shared by actual callers. experiments/early/ preserves earlier implementations needed for history or reproduction. Read [incremental structure guidance](repository-structure.md) before adding packaging or workflow machinery.

configs/ holds execution/evaluation settings worth separating from code. private_work/ holds untracked raw inputs, subject-level output, models, logs, and large artifacts under local retention and access rules. private_work/experiments/<experiment>/a<N>/ separates execution attempts; once a failed attempt is recorded in its card or attempts.json, delete its bulky outputs. results/ holds only shareable aggregates, tables, and figures permitted by the repository, linked to generation code. A private_work directory name does not determine statistical public/private roles or a DP guarantee.

registry/ contains derived experiment/discussion/output indexes and path mappings. Generate it from authoritative records; do not maintain it as another manual source of truth. scripts/ contains repository-wide indexing, search, execution-status, or event tools. tests/ checks real structure, paths, input contracts, and analysis behavior.

## One Experiment Across The Depths

```text
records/experiments/2026-11-03-x154m-gradient-difference-reuse.md
experiments/explore/x154m_gradient_difference.py
configs/x154m_gradient_difference.json
private_work/experiments/2026-11-03-x154m-gradient-difference-reuse/a3/
```

Use this naming: the date is the first-record date; the stable ID links card, code, config, and outputs; the topic describes the question; a<N> identifies an execution attempt. Executable filenames omit the date because the card owns chronology. Use the project's output helper, such as experiments.lib.paths.out_dir when it exists, to maintain the card-to-output relationship. The x154m ID and its DP topic are only an example.

## Active Recovery State And Units

.plans/HANDOVER.md records what is running and the next safe waiting/resume action. .plans/ledger.json points to active work, user constraints, deadlines, next action, and authoritative records. .plans/ is current recovery state; records/ is detailed research history. If the project already has equivalent paths, preserve them.

An experiment has one question/method/comparison/evaluation scope. An attempt is an operational execution or recovery instance and can contain several seeds or stages. A seed is a random realization, not automatically a new subject/device/acquisition. A stage is preparation, capture, training, analysis, or figure generation. A judgment states supported, contradicted, or unresolved findings. A handover preserves continuity without declaring the research complete.

Local disclosure thresholds, PDF caches, device names, datasets, Python/GPU settings, and registry commands come from repository instructions. The supplied dp example's aggregation threshold is not a global rule.
