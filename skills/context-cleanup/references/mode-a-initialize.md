# Mode A — Initialize

Read this only when Mode A is the mode. The repo has no `CLAUDE.md`, or one
without a `## Context layout` section: scaffold the layout, survey the repo,
and adopt whatever is already written into the right tier.

---

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

