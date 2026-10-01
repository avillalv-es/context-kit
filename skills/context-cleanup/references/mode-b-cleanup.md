# Mode B — Cleanup

Read this only when Mode B is the mode (the `cleanup` argument). The layout
already exists: audit it, show the user a table, and rebalance only after they
agree.

**Some of `CLAUDE.md` is not yours to classify.** The plugin owns everything
between `<!-- context-kit:begin <id> -->` and its end marker, any unmarked
`## Context layout` or `## Lean execution` block written by 0.4.x, and any
`<!-- context-kit:off <id> -->` line. Skip all of it in B2, never propose
moving, trimming or deleting it, and leave it alone in B4; the next
`/context-init` rewrites it from the plugin anyway. It still counts toward the
200-line cap, so in B1 report its line count apart from the rest.

This is the step where knowledge gets silently lost, which is why B3 stops
and does not proceed on implied approval.

---

### B1 — Inventory

Report, without editorializing:
- `CLAUDE.md` line and character count, against the 200-line cap, with the
  managed lines (see above) counted separately.
- Every file in `.claude/rules/`, its line count, and whether it has a `paths`
  field or loads unconditionally.
- Every skill, with its description.
- Every file in `knowledge/`, and whether `INDEX.md` lists it.

### B2 — Classify

Apply the classification test to every line of `CLAUDE.md` outside the managed
blocks. Present as a table: line or block, proposed tier, destination path, one-sentence reason.
Mark rows decided by tie-break.

Keep each reason to one line, in the form
`L<line>: <verdict> <what>. <destination>.` where verdict is one of
`tier1: / tier2: / knowledge: / skill: / delete:`. A large repo produces a long
table, and prose per row turns the audit into the thing it is auditing.

Anything classified `skill:` is a capture candidate — hand those to the
`skill-capture` skill rather than writing the SKILL.md inline here.

Then flag separately:
- Anything duplicated across tiers.
- `CLAUDE.md` naming individual `knowledge/` files instead of one line
  pointing at `knowledge/INDEX.md`. This is the same duplication as any
  other cross-tier repeat, just easy to miss because it looks like routing
  rather than restating — B1 already asked whether `INDEX.md` lists each
  file; ask the reverse too, whether `CLAUDE.md` lists them a second time.
- Rules files with no `paths` field, which are loading unconditionally.
- Any description written as a capability statement rather than a trigger
  condition, since those will not fire.
- Knowledge files over roughly 300 lines, which should split by subtopic so a
  lookup does not pull the whole file.

### B3 — Stop

Show the table and wait. Move nothing. Do not proceed on implied approval. If
the user approves a subset, move only that subset.

### B4 — Execute

Move what was approved. Then remove or shorten anything in `CLAUDE.md` the
move made redundant, and say which lines you removed.

### B5 — Verify

- `CLAUDE.md` before and after counts.
- Which files load at session start versus conditionally.
- Confirmation that nothing is duplicated across tiers.
- Every tie-break decision, restated so the user can revisit it.

Tell the user to restart the session and run `/context` to see the real change.

---

