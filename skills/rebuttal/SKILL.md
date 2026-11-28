---
name: rebuttal
description: Run a paper's review response (rebuttal, author response, OpenReview discussion) from the saved review page through the professor's feedback rounds to the posted text. Use when reviews arrive, when drafting or revising a response, when the professor sends rebuttal guidance or an edited draft, and when recording what was posted. Not for writing the manuscript itself, which is paper-writing.
---

# Rebuttal

The student saves the full review page, the professor steers and edits the English draft, and the response goes through several drafts before it is posted. Keep one venue's rebuttal in `docs/venues/<venue>/rebuttal/` as five kinds of flat files:

| File | Content | Rule |
|---|---|---|
| saved page (`.html`, `.pdf`) | the review page as downloaded | never edited |
| `r<N>-reviews.md` | round N reviews, extracted verbatim | frozen once checked against the page |
| `r<N>-response.md` | only the text to be posted, one section per channel | first line `posted <date>` once posted, then frozen |
| `professor.md` | the professor's written guidance, verbatim under a date heading | append only |
| `ledger.md` | one row per reviewer point | the only working table |

Create no strategy, issue, analysis, or status files beside them. The current state is one line in `docs/venues/<venue>/README.md`, overwritten as it changes, next to the venue's rules: response limit and its unit, deadline in UTC and local time (convert an epoch value), channels, and whether attachments or a revised PDF are allowed. Evidence experiments are ordinary experiment cards under `research-repo-protocol`; a genuinely hard strategy choice is a discussion round under `records/rounds/`.

## Reviews arrive

Extract the reviews from the saved page source, not from a rendered copy, because copying drops inline math. HotCRP embeds each review as JSON in `hotcrp.add_review(...)` and the response limit in `set_response_round(...)`. Check symbols and numbers in the extraction against the page, then record the venue rules in the README. Material prepared before the reviews stays frozen in `planning/`; carry what still applies into the ledger.

## Ledger and drafts

Ledger columns: ID (reviewer letter and number, `A1`), concern as a short verbatim quote, response plan, where `r<N>-response.md` answers it, evidence path, promised manuscript change, status. A point repeated in a later round gets an `r<N>:` note in its existing row. Every row ends answered, deliberately left out with a reason, or open.

Write a complete draft within the limit early, marking anything not yet established as `[pending: <what>]`, and revise that same file.

## Professor rounds

- Add written guidance verbatim to `professor.md` and follow it. When it conflicts with a project rule or the evidence, put the question to the professor through the user instead of overriding it, and record the answer in the affected ledger row.
- Commit an edited draft verbatim as the new `r<N>-response.md`. In the next commit fix only factual errors, limit overruns, and rule violations, and send the professor that diff as the list of changes. The professor's wording is author-owned.

## Before posting

Check once, then use at most one independent reviewer under `review-budget`; a reviewer that refuses or returns nothing counts as no review.

- Every number traces to the submitted manuscript or an evidence file, and every claim stays within the scope that source supports.
- Every promised manuscript change is in the ledger.
- No `[pending ...]` marker, internal experiment ID, repository path, or identifying detail remains, and links follow the venue rule.
- Each channel fits the limit as the venue's form counts it; otherwise count whitespace-separated words or characters including spaces.

## After posting

The user pastes the text into the portal. Ask for any edits made there and apply them so `r<N>-response.md` equals what was posted, add `posted <date>` as its first line, and update the README state. When the decision arrives, record it in the README and confirm that the next manuscript version contains every promised change.
