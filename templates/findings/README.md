# findings/

Working logs from long analysis runs. Copy this file to `<repo>/findings/`
alongside a `.gitkeep`.

## Why this folder exists

Analysis that exists only in the conversation does not survive a long session.
Compaction summarizes it, and the specifics — the exact line, the exact
number, the dead end you already ruled out — are the first things a summary
drops. Those specifics are precisely what you would otherwise have to
re-derive.

A finding appended to a file survives verbatim. A finding that exists only in
the transcript does not.

## The convention

- **One file per investigation**, named for the investigation, not the date
  alone: `feature-3-qa.md`, `production-readiness-audit-2026-09-08.md`.
- **Append as you go.** Not at the end. A finding written after the compaction
  is a finding written from memory.
- **Append, never overwrite.** A later run adds a section; it does not replace
  the earlier one. The disagreement between two runs is itself information.
- **Date each entry**, absolutely, not relatively. "Last week" is unreadable in
  three months.

## Entry shape

```markdown
## 2026-09-19 — <what was investigated>

**Question:** <what you were actually trying to settle>

**Method:** <what you ran or read, concretely enough to repeat>

**Finding:** <the conclusion>

**Confidence:** confirmed | inferred | unverified
<!-- confirmed = you ran it and saw it
     inferred  = it follows from something you confirmed
     unverified = it is the best current guess and nobody has checked -->

**Evidence:** <the line, the number, the output — the part a summary would drop>

**Dead ends:** <what you ruled out, so the next run does not repeat it>
```

The `confidence` line does the most work over time. Six months later, the
difference between "we measured this" and "we assumed this" is the difference
between a fact and a bug waiting to happen, and nothing else in the file
records it.

## Lifecycle

- A finding that proves **durable** gets promoted into `knowledge/` as
  reference material, and the findings entry stays where it is as the record of
  where it came from.
- A finding that proves **wrong** gets a correction appended *in the same
  file*. Do not delete it — the next run needs to know that path was already
  walked.
- A finding that is **still open** stays here. This folder is allowed to
  contain unresolved things; that is what distinguishes it from `knowledge/`.

## What does not go here

Durable reference material — that is `knowledge/`. Conventions and rules —
those are `.claude/rules/`. This folder is a working log with a shelf life, and
keeping it that way is what stops it from becoming a second, unindexed
knowledge base.
