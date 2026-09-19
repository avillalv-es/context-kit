---
name: context-cleanup
description: Use when the user runs /context-init, or asks to set up, initialize, clean up, tier, audit, reorganize, or trim this repo's three-tier context layout or its CLAUDE.md, or asks which tier a piece of project knowledge belongs in. Also use in Mode 0 when the context-kit session-start hook reports that this project has no context layout yet. Scaffolds .claude/rules/, knowledge/ and findings/, and rebalances CLAUDE.md against a 200-line cap. Explicit invocation or hook request only. Never invoke this during an unrelated task.
---

# Context layout: initialize and clean up

This skill has three modes. Pick one, announce it in a single line, and follow
that mode's workflow.

- **Mode 0: Bootstrap** — the session-start hook asked for it, or the user
  wants the layout in place with no survey. Scaffold and stamp the marker,
  nothing else. Cheap, idempotent, always safe to run.
- **Mode A: Initialize** — no `CLAUDE.md`, or one that lacks a
  `## Context layout` section. Scaffold the layout, survey the repo, and adopt
  any existing content into it.
- **Mode B: Cleanup** — the layout already exists. Audit and rebalance it.

Both modes share one goal: place every piece of knowledge in the cheapest tier
that still guarantees it gets used. Placing something too high is not a safe
default. It taxes every session and every subagent, and it reduces adherence
to everything else in the file.

---

## The classification test

Used by both modes. For each line or coherent block of knowledge:

> If I never saw this, would I get something wrong on a task that has nothing
> to do with this knowledge's subject?

- **Yes** → Tier 1. `CLAUDE.md`. Rare.
- **No, but it applies whenever certain files are touched** → Tier 2.
  `.claude/rules/<topic>.md` with a `paths` list.
- **No, it is reference or narrative** → Tier 3. `knowledge/<topic>.md`.
- **No, it is a procedure that repeats** → Tier 3.
  `.claude/skills/<name>/SKILL.md`.
- **It is derivable by reading the codebase** → Delete. Directory trees,
  dependency lists, file inventories, and architecture summaries all belong
  in this bucket. Do not carry them anywhere.

Break ties toward the lower tier and mark those choices, because the error
costs are asymmetric. A tier 2 rule that should have been tier 1 produces one
visible mistake the user can correct. A tier 1 entry that should have been
tier 2 produces invisible drag on every session forever.

---

## Mode 0: Bootstrap

The automatic path. The session-start hook runs this when a project has no
`## Context layout` marker. It is deliberately the cheapest useful thing: no
survey, no judgment, no questions. Do it, say one line, and get back to
whatever the user actually asked for.

### 0.1 — Scaffold

Create, without overwriting anything that exists:

```
.claude/rules/.gitkeep
knowledge/.gitkeep
knowledge/INDEX.md
findings/.gitkeep
```

`knowledge/INDEX.md` gets a heading and one line explaining that each entry is
a topic file named for what someone would search for.

### 0.2 — Stamp the marker

If `CLAUDE.md` does not exist, create it with a title line and the stub from
A4. If it exists, **append** the stub — never overwrite, never reorder, never
reword what is already there.

### 0.3 — Report, in one line

```
context layout bootstrapped: <files created>. For a full survey, run /context-init.
```

Do not survey the repo. Do not propose moves. Do not classify anything. That is
Mode A, and it is the user's call to run it.

---

## Mode A: Initialize

### A1 — Survey

Explore the repo enough to write accurately. Read package manifests, config
files, CI definitions, any README, and enough source to identify conventions.
Look specifically for things that would be **non-obvious to someone reading
the code**, since that is the only content worth writing down.

Do not inventory the directory structure. That is derivable.

**Aim the survey at the kind of project this is.** The default questions suit a
service or an application; they are close to useless elsewhere.

- **Data, analytics or notebooks** — execution order that is not top-to-bottom,
  dtype and schema assumptions that break silently, where seeds are set and
  what is non-deterministic without them, how credentials reach the notebook,
  which cells are expensive to re-run, and which outputs are committed on
  purpose. There is often no build or lint command at all; do not invent one.
- **Pipelines, dbt, ETL** — what triggers a run, what is idempotent and what is
  not, backfill procedure, and which models are contract-bound downstream.
- **Libraries** — the public surface and what is deliberately not exported,
  plus the compatibility promise.
- **Infrastructure** — what is applied by hand versus by CI, and what is
  dangerous to `plan` against production.

If the repo has no manifest and no test runner, say so plainly rather than
writing a Commands section full of guesses.

### A2 — Scaffold

Create, without overwriting anything that exists:

```
.claude/rules/.gitkeep
knowledge/.gitkeep
knowledge/INDEX.md
findings/.gitkeep
```

`knowledge/INDEX.md` gets a heading and one line explaining that each entry is
a topic file named for what someone would search for.

### A3 — Write or adopt CLAUDE.md

**If no `CLAUDE.md` exists**, write one with only these sections, omitting any
that has no real content. Target under 100 lines for a first version.

- **Commands** — the build, test, lint, and run commands, verified against the
  actual manifest rather than assumed.
- **Conventions** — only where they differ from the tool's defaults or from
  what a competent developer would guess. If it matches the default, leave it
  out.
- **Pitfalls** — things that have a non-obvious failure mode. This is the
  highest value section, so weight your survey toward finding these.
- **Where knowledge lives** — pointers to `knowledge/` and `.claude/rules/`.
  Each pointer must state the trigger for reading, not just the path.
  "Chart mechanics are in `knowledge/charts.md`" is inert. "Read
  `knowledge/charts.md` before modifying any chart config" is not.

Do not include: directory trees, dependency lists, architecture overviews,
project history, or anything else derivable by looking.

**If `CLAUDE.md` exists**, do not replace it. Run the Mode B classification
pass over its current contents, then continue into A4.

### A4 — Append the stub

Append this to `CLAUDE.md` verbatim. Do not reword it, and do not summarize
it. It is the only thing keeping the layout from re-accumulating between
cleanups.

```markdown
## Context layout

This project uses a three-tier layout. Do not add knowledge to this file on
your own initiative. If something seems worth keeping, say so in one line and
let me decide.

- Conditional knowledge lives in `.claude/rules/` with `paths` frontmatter.
- Reference and procedures live in `knowledge/` and `.claude/skills/`.
- A procedure that repeats gets captured into `.claude/skills/`. Tell me in one
  line after you create it; do not add it here.
- This file is capped at 200 lines.

To reorganize any of it, run `/context-init`.
```

### A5 — Report

- What you created, as a file list.
- `CLAUDE.md` line count.
- If you adopted existing content, the table from Mode B phase 2 showing what
  moved where.
- Anything you found during the survey that looked like a pitfall but that you
  could not confirm, so the user can verify it.

Tell the user to restart the session and run `/context` for a baseline number.

---

## Mode B: Cleanup

### B1 — Inventory

Report, without editorializing:
- `CLAUDE.md` line and character count, against the 200-line cap.
- Every file in `.claude/rules/`, its line count, and whether it has a `paths`
  field or loads unconditionally.
- Every skill, with its description.
- Every file in `knowledge/`, and whether `INDEX.md` lists it.

### B2 — Classify

Apply the classification test to every line of `CLAUDE.md`. Present as a
table: line or block, proposed tier, destination path, one-sentence reason.
Mark rows decided by tie-break.

Keep each reason to one line, in the form
`L<line>: <verdict> <what>. <destination>.` where verdict is one of
`tier1: / tier2: / knowledge: / skill: / delete:`. A large repo produces a long
table, and prose per row turns the audit into the thing it is auditing.

Anything classified `skill:` is a capture candidate — hand those to the
`skill-capture` skill rather than writing the SKILL.md inline here.

Then flag separately:
- Anything duplicated across tiers.
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

## Authoring standards

**Tier 1.** Router form. Names where knowledge lives and the condition for
reading it. Does not contain the knowledge. Write the trigger, not just the
location.

**Tier 2.** Scope the `paths` list as narrowly as the knowledge actually
applies. Never a bare `**/*`. Group by domain, not by the session that
produced it. Add to an existing matching file rather than creating a sibling.

Note that path-scoped rules do not survive compaction until something
re-triggers them. If a rule is load-bearing during long autonomous runs, flag
it for tier 1 even when it is technically file-specific.

**Tier 3.** One topic per file, named for the words someone would search for,
with a line in `INDEX.md`. Filenames and folder structure are the retrieval
index. A repeated procedure becomes a skill whose description enumerates the
situations and vocabulary that will appear in a real request.

## Also audit the skills

`.claude/skills/` accumulates on its own now — `skill-capture` creates skills
without asking. That makes pruning them part of this job:

- **Near-duplicates.** Two descriptions competing for the same trigger means
  neither fires reliably. Merge them.
- **Descriptions written as capability statements** rather than trigger
  conditions. Those never fire, so the skill is pure weight in the picker.
- **Bodies over ~100 lines.** Split the reference material out into
  `knowledge/` and link it, so firing the skill does not drag it all in.
- **Skills nothing has used.** Ask before deleting; a skill that has not fired
  may have a weak description rather than no purpose.

## Opportunities to raise

Propose, do not implement — with one exception. **Skills are no longer in this
list:** `skill-capture` creates them outright. The rest still need your say-so:

- **A subagent**, when work here is genuinely isolatable and verbose enough to
  dump large tool output into the main window. Specialization alone is not
  sufficient reason. Any proposal needs a trigger-condition description, a
  `skills` list preloading only its own domain, a return contract stating
  exactly what comes back, and `mcpServers` scoped to the agent if it needs
  tools the main session does not.
- **A hook**, when a rule would be an incident rather than an annoyance if
  ignored once. Hooks cost no context until they fire, so a guarantee is
  cheaper than a request.
- **Externalization**, if the user runs long analysis sessions and loses
  findings to compaction. Findings appended to files survive verbatim.
  Findings that exist only in conversation do not.

## Throughout

- Record the why, not the what. Rationale, pitfalls, and conventions that
  differ from defaults earn their place. Anything derivable does not.
- Preserve the user's wording when moving a line. You are relocating
  knowledge, not rewriting it.
- Never delete something you cannot classify. Flag it and ask.
- Make ordinary working-tree edits. Do not commit.
