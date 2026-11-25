# Manuscript Workspace

Use this procedure for any work that creates, versions, renders, submits, or uploads a manuscript, or that handles a venue's reviews. The research-repo-protocol [directory roles](../../research-repo-protocol/references/directory-roles.md) define where each file lives; this document says what to do at each event. The project AGENTS.md manuscript section holds project values: the current series, manuscripts that need XeLaTeX, page limits, the render command, and the frozen list.

## Invariants

- `docs/paper/` is the supervisor's Overleaf project root, and uploading it as is must render every manuscript. It holds only what LaTeX reads: `.tex`, `.bib`, class/style/bst files, venue templates, and figures. The supervisor sees every file in the Overleaf tree, so notes, READMEs, agent rules, scripts, figure data, provenance, logs, and rendered PDFs live outside it.
- Each main document builds from its own folder, as Overleaf compiles a main file in a subfolder (latexmk `-cd`). Paths inside a manuscript are relative to that folder, so a self-contained folder renders without TeX edits after a move.
- Main documents have distinct file names across the tree. Overleaf has an open bug ([overleaf#1374](https://github.com/overleaf/overleaf/issues/1374)) where compiling `folder/main.tex` builds a root `main.tex` of the same name instead.
- A version is never edited after the next version exists, and a submission folder is never edited after submission. Change produces a new version, not an edit to a frozen one.
- Rendered PDFs go to `docs/paper-pdf/` at the same relative path and stay untracked, because the source reproduces them. Only the PDF actually sent to a venue is kept, frozen, in `docs/venues/<venue>/record/`.

## Events

- **New version:** copy the latest `main<K>_v<N>.tex` at the root to `main<K>_v<N+1>.tex` and edit the copy. Earlier versions stay unchanged.
- **Replacing a figure an older version reads:** move the old file to `figures/v<N>/`, change only that older version's path to it, then overwrite the current file. Current figures use version-neutral names.
- **Submission:** copy the submitted version with its bib, styles, and the figures it reads into `submissions/<venue>/` at the same relative paths so the folder builds alone, and freeze it. Name its main file so no other main document shares the name, for example `<venue>.tex`. Keep the root version byte-identical in content while its series is current. Store the PDF actually sent in `docs/venues/<venue>/record/`.
- **Paper with its own template:** write it in `submissions/<venue>/` from the start.
- **New series:** when the supervisor starts `main<K+1>`, move `main<K>_v*.tex` with its bib and styles into `main<K>/`, and copy the figures they read, including `figures/v<N>/`, to `main<K>/figures/` at the same relative paths. No TeX edits are needed.
- **Reviews:** save them verbatim in `docs/venues/<venue>/rebuttal/reviews/` and freeze them. Write analyses as numbered documents (`01-<topic>.md`) and reply drafts in `rebuttal/drafts/`, keeping the supervisor's text verbatim. Rebuttal experiments are ordinary experiment cards linked from these documents. A revised manuscript is the next version at the root.
- **Evidence record:** `docs/venues/<venue>/record/README.md` is the single current record of version changes, responses to criticism, and evidence links. Update it in the same task as the manuscript or evidence change instead of writing dated summaries.
- **Venue closes:** leave `docs/venues/<venue>/` and `docs/paper/submissions/<venue>/` in place and add both to the project's frozen list. A new cycle opens a new venue folder linked by one carry-over document in its `planning/`.

## Render

Use the project's render command when AGENTS.md names one. Otherwise build in a temporary directory, so no log or auxiliary file lands in the Overleaf tree, and copy the PDF to the mirrored path:

```bash
out="$(mktemp -d)"
latexmk -pdf -cd -interaction=nonstopmode -halt-on-error -outdir="$out" docs/paper/<path>/<name>.tex
mkdir -p docs/paper-pdf/<path> && cp "$out/<name>.pdf" docs/paper-pdf/<path>/<name>.pdf
```

Use `-xelatex` instead of `-pdf` for the manuscripts AGENTS.md lists. Check the log for undefined references and citations and for page-limit violations before reporting the render; show the user the `docs/paper-pdf/` path.

## Upload

Upload a zip of `docs/paper/` or push it through Overleaf's Git integration. One upload accepts at most 180 files and 50 MB, a project at most 2000 files, and a zip at most 7 MB of editable text; for a larger project, create it from the root files and `figures/`, then upload the other folders. The compiler and main document are project-wide Overleaf settings, so tell the supervisor which main file and compiler to select. When the supervisor edits on Overleaf, bring those edits back before the next local edit; never overwrite the Overleaf project with an older tree.

## Completion check

Before reporting manuscript work as done, run these checks from the repository root. They must print nothing except files AGENTS.md names as venue-template requirements:

```bash
find docs/paper -type f \( -name '*.md' -o -name '*.txt' -o -name '*.py' -o -name '*.sh' -o -name '*.ipynb' \
  -o -name '*.csv' -o -name '*.json' -o -name '*.log' -o -name '*.aux' -o -name '*.fls' -o -name '*.fdb_latexmk' \
  -o -name '*.synctex.gz' -o -name '*.out' -o -name '*.blg' -o -name '.DS_Store' \) -print
find docs/paper -name '*.pdf' | while read -r f; do [ ! -e "${f%.pdf}.tex" ] || echo "rendered PDF: $f"; done
grep -rl --include='*.tex' '\\documentclass' docs/paper | xargs -n1 basename | sort | uniq -d
```

The first finds non-LaTeX files, the second rendered PDFs beside their source, and the third main documents sharing a name. Move what they find to its place under the directory roles, and give a duplicated main file a distinct name.
