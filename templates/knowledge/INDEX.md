# Knowledge index

One entry per topic, named for what someone would search for. The filename and
the folder are the retrieval index — if you cannot find a topic by its name,
the name is wrong.

<!--
  Tier-3 template. Copy to <repo>/knowledge/INDEX.md and fill in.

  The "Read it when" column is the point of this file. A table of filenames and
  descriptions is a catalogue; a table of filenames and reading conditions is a
  router. Write the condition.

  If most of the project's reference material already lives in `docs/` or in
  per-folder READMEs, do NOT copy it here. Point at it. One place to look, one
  place to update — a second copy drifts from the first and the drift is
  invisible until it causes a wrong decision.
-->

Most of this project's reference material lives in `<docs/ or wherever>` and in
the per-folder READMEs, and is **not** duplicated here. This index points at all
of it so there is one place to look.

## In this folder

| File | Read it when |
|---|---|
| [`<topic>.md`](<topic>.md) | <The condition. "Before any git operation." "When a document cites a file that is not on disk." Not "explains git state."> |

## The record — `<docs/>`

| File | What it settles |
|---|---|
| `docs/<file>.md` | <What questions this file is the answer to. Mark anything that is agreed between parties and must not be changed unilaterally.> |

## Conventions for this folder

- **One topic per file.** Named for the words someone would search for.
- **Split past ~300 lines.** A lookup pulls the whole file, so a long file
  drags eight unrelated subtopics along with the one that was wanted.
- **Every file gets a row above.** A knowledge file missing from this index is
  a file nobody will find.
- **Do not quote a total from a register — count it.** Any number written into
  a summary line goes stale the next time the underlying file changes, and
  then gets asserted as fact.
