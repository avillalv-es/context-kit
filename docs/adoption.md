# Adoption

How to roll this into a repo, and how to keep it from re-accumulating.

---

## A repo with no `CLAUDE.md`

Run `/context-init`. It selects **Mode A** and:

1. **Surveys** the repo — manifests, config, CI, README, enough source to
   identify conventions. It looks specifically for things that would be
   *non-obvious to someone reading the code*, since that is the only content
   worth writing down. It does not inventory the directory structure.
2. **Scaffolds** `.claude/rules/`, `knowledge/` with an `INDEX.md`, and
   `findings/`.
3. **Writes** a first `CLAUDE.md`, targeting under 100 lines.
4. **Stamps the managed sections** (below), which keep the layout from
   re-accumulating.
5. **Reports** what it created, the line count, and anything that looked like a
   pitfall it could not confirm — so you can verify it rather than inherit a
   guess.

Restart the session afterwards and run `/context` for a baseline number.

## A repo that already has a `CLAUDE.md`

Also Mode A, but it **adopts** rather than replaces: it runs the classification
pass over the existing contents first, then continues with the scaffold. Your
file is never overwritten.

## A repo that already has the layout

Run `/context-init` again. It selects **Mode R**, a refresh, and touches only
what the plugin owns:

1. Creates any layout folder that has gone missing and overwrites nothing.
2. Stamps the managed sections into `CLAUDE.md` (see below): adds the ones
   that are missing, rewrites the outdated ones in place, and leaves alone any
   you turned off.
3. If `CLAUDE.md` holds nothing but those sections, because the hook
   bootstrapped it, runs the survey Mode A would have run.

Run it after a plugin update, and whenever a managed section looks stale.

To audit instead, run `/context-init cleanup`. It selects **Mode B** and
checks line counts against the cap, every rule and whether it has a `paths`
field, every skill and its description, every knowledge file and whether the
index lists it.

Then it classifies, and **stops**. It shows you a table — line or block,
proposed tier, destination, one-sentence reason, tie-breaks marked — and moves
nothing until you approve. Approve a subset and only that subset moves. The
managed sections are the plugin's, so it does not classify them.

Run it when any of these is true:

- `CLAUDE.md` has grown past its cap.
- You have finished a large feature and the file absorbed notes during it.
- Something in tier 1 turned out to be stale.
- You are onboarding someone and want to know what is actually load-bearing.

---

## The managed sections

Mode A and Mode R stamp two sections into `CLAUDE.md`, each between
`<!-- context-kit:begin <id> -->` and `<!-- context-kit:end <id> -->`. Claude
Code strips those comments before loading the file, so the markers cost no
tokens. The text is not written here and not by the model: it lives in
`templates/sections/` (and, for Lean execution, is generated from
`hooks/rules.md`), and `scripts/claude-sections.sh stamp CLAUDE.md` copies it
in verbatim. A section is outdated when the text between its markers differs
from what the plugin would write now, so a plugin update reaches every repo on
its next `/context-init`. Edits inside the markers are overwritten; change the
template instead.

To drop one, run `/context-init off <id>`: the block becomes a single
`<!-- context-kit:off <id> -->` line that a refresh never re-adds, and
`/context-init on <id>` puts it back.

The Context layout section is the one that keeps a clean layout from drifting
back, and two of its clauses are easy to edit out by accident:

- **The ban on adding knowledge on its own initiative.** Without it, every
  session that learns something appends a line, and the file grows
  monotonically because nothing ever removes one.
- **"Say so in one line and let me decide."** This keeps the knowledge from
  being *lost* instead. The agent still surfaces what it learned; you just
  choose the tier. Drop this clause and you trade accumulation for amnesia.

---

## `findings/` — surviving compaction

Scaffolded but easy to ignore, and it solves a real problem: analysis that
exists only in the conversation does not survive a long session. Compaction
summarizes it, and the specifics — the exact line, the exact number, the thing
you would otherwise have to re-derive — are the first casualties.

The convention: **findings from a long analysis run are appended to a file in
`findings/`, not reported only in chat.** Appended, so a later run does not
overwrite an earlier one. One file per investigation, named for the
investigation.

This is not tier 3 reference material. It is a working log with a shelf life.
When a finding turns out to be durable, promote it into `knowledge/`; when it
turns out to be wrong, say so in the same file rather than deleting it, so the
next run does not re-derive the same dead end.

---

## Maintaining it

**Quarterly, or after anything large:** run `/context-init cleanup` (Mode B).

**When a tier-1 line proves stale:** that is the visible failure the downward
tie-break is designed to produce. Fix the line, then ask whether it should have
been a number at all, or a hook that checks it.

**When a rule gets ignored:** look at its `paths` before rewriting the text.
Most ignored rules were never loaded.

**When you add a fourth file to `.claude/rules/` for the same area:** merge.
Rules should be grouped by domain, and three files covering one subsystem means
the grouping drifted toward sessions.

---

## A note on shared repos

If the repo is governed — CODEOWNERS on `CLAUDE.md`, a policy against editing
`.claude/settings.json`, required PR checks — then `/context-init` proposing
moves is fine, but landing them is a normal change: branch, issue, PR, review.
The skill makes ordinary working-tree edits and does not commit, specifically
so this stays your call.
