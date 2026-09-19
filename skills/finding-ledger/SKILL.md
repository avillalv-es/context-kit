---
name: finding-ledger
description: Use when you have settled something worth not re-deriving, ruled out a dead end, or had a conclusion corrected; when the user asks to record, log or save a finding; when starting a long investigation that will outlive one context window; when the user asks what was already tried, what the dead ends were, or to summarize the findings log; or runs /finding. Also use before a compaction on a long analysis run. Do not use for durable reference material - that is knowledge/ - or for conventions, which are .claude/rules/.
---

# Finding ledger

A finding that exists only in the transcript does not survive compaction.
Compaction summarizes, and the specifics — the exact line, the exact number,
the dead end already ruled out — are the first things a summary drops. Those
specifics are precisely what would otherwise be re-derived.

Append as you go. Not at the end: a finding written after the compaction is a
finding written from memory.

## Record one

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/findings.sh" record \
  --file <investigation-name> \
  --question "what you were actually trying to settle" \
  --method   "what you ran or read, concretely enough to repeat" \
  --finding  "the conclusion" \
  --outcome  useful \
  --confidence confirmed \
  --sources  "path/one.py, docs/two.md"
```

One file per **investigation**, not per session — `cache-audit`, not
`tuesday`. Entries are appended; nothing is ever overwritten. If a finding
proves wrong later, append a `corrected` entry in the same file. Do not
delete the original: the next run needs to know that path was already walked.

### The fields that do the work

**`--outcome`** is the whole aggregation mechanism.

| | When |
|---|---|
| `useful` | it answered the question and you would look there again |
| `dead_end` | it led nowhere. Recording this is what stops the next run repeating it |
| `corrected` | you concluded something and it turned out wrong. Needs `--correction` |

**`--sources`** is what you *leaned on*, which for a `corrected` entry means
what misled you. That is deliberate: a source that keeps producing
corrections should stop looking trustworthy.

**`--confidence`** — `confirmed` (you ran it and saw it), `inferred` (it
follows from something you confirmed), `unverified` (best current guess,
nobody checked). Six months on, the difference between "we measured this" and
"we assumed this" is the difference between a fact and a bug waiting to
happen, and nothing else in the file records it.

Never record a credential value. Record the *name* of the variable and where
it comes from.

## Aggregate

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/findings.sh" reflect --if-stale
```

Writes `findings/LESSONS.md`: preferred sources, tentative ones, contested
ones, known dead ends, corrections. Deterministic — no model, stable order,
the same bytes for the same input on the same day. `--if-stale` makes it a
no-op when nothing has been appended since the last run, so it is cheap
enough to run at the start of a session.

Two rules decide what it says, and both are there to stop it lying:

- **A single entry never mints a trusted source.** Two corroborating `useful`
  entries before anything is called preferred. One confident note is how a
  wrong answer becomes a fact.
- **Signals decay, 30-day half-life.** A dead end found last week outweighs a
  success from March. Without this the ledger grows more confident the more
  out of date it gets.

Both are tunable: `--min-corroboration N`, `--half-life N`.

## Reading it

Read `LESSONS.md` for orientation, then verify. It says where to look, not
what is true. A `preferred` source is where answers have come from before —
if the code has moved since, the lesson is stale and the date in the entry is
how you tell.

Treat "known dead ends" as a real constraint. Re-deriving one is the single
most expensive thing a long investigation does.

## Lifecycle

- A finding that proves **durable** is promoted into `knowledge/` as reference
  material. The findings entry stays where it is, as the record of where it
  came from.
- A finding that proves **wrong** gets a `corrected` entry appended in the
  same file.
- A finding still **open** stays here. This folder is allowed to hold
  unresolved things; that is what separates it from `knowledge/`.

`findings/` is a working log with a shelf life. Keeping it that way is what
stops it becoming a second, unindexed knowledge base.
