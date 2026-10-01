# Mode A — Initialize

Read this only when Mode A is the mode. The repo has no `CLAUDE.md`, or one
with no context layout (no `## Context layout` heading and no `context-layout`
marker): scaffold the layout, survey the repo, and adopt whatever is already
written into the right tier. Mode R reuses A1 to A3 for a file that was only
bootstrapped.

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
findings/README.md
```

`knowledge/INDEX.md` gets a heading and one line explaining that each entry is
a topic file named for what someone would search for. `findings/README.md` is
a copy of `${CLAUDE_PLUGIN_ROOT}/templates/findings/README.md`, made only when
it is absent, so the convention travels with the folder.

### A2b — Initial ingest

Whatever project markdown already exists (a root `PROGRESS.md`, `docs/`,
notes, ideas) is where most of what this layout should hold is written, and
nothing has read it yet. Run the `context-sync` skill now, in the
**foreground**: spawn its routing subagent with `run_in_background: false` and
wait for it. On a first run every source is `new`, so all of the root and
`docs/` markdown is routed into `knowledge/`, `findings/`, `.claude/rules/` and
`.claude/skills/`. Ignore any `sections` line it reports; A4 stamps those. When
the routing is reviewed, record everything as routed:

```
sh "${CLAUDE_PLUGIN_ROOT}/scripts/context-sync.sh" mark --all
```

That also covers sources the router judged to be status chatter and left where
they were. If `check` printed nothing there was no markdown, so skip this step.
Keep the skill's one-line summary for A5.

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
  A rule earns its own pointer — each has a different `paths:` trigger, and
  that difference is the information. `knowledge/` does not: write one line,
  "Topic index for everything else: `knowledge/INDEX.md`", and stop. Naming
  each knowledge file here too puts the same fact in two places, and the
  second copy drifts from the first the moment either one changes without
  the other. `/context-graph` flags a `knowledge/` file nothing routes to —
  if `CLAUDE.md` names every file directly, that flag fires on `INDEX.md`
  itself, which is a sign the pointer was skipped, not a sign to add one
  more line naming `INDEX.md` too.

Do not include: directory trees, dependency lists, architecture overviews,
project history, or anything else derivable by looking.

**If `CLAUDE.md` exists**, do not replace it. Run the Mode B classification
pass over its current contents, then continue into A4.

### A4 — Stamp the managed sections

```
sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" stamp CLAUDE.md
```

This appends the Context layout section, then the Lean execution section (A4b),
each between `context-kit` markers. Their text lives in
`${CLAUDE_PLUGIN_ROOT}/templates/sections/`, and the script writes it
verbatim; do not reword it, summarize it, or type it out yourself. The Context
layout section is the only thing keeping the layout from re-accumulating
between cleanups. Pass the script's output on in A5.

### A4b — The Lean execution section, and why it is in `CLAUDE.md`

The script builds this section from `${CLAUDE_PLUGIN_ROOT}/hooks/rules.md` at
the current lean level (`--level lite|full|ultra` overrides it). `CLAUDE.md`
loads every session whether or not hooks run, which makes it what keeps the
ruleset applying where a managed Claude Code policy blocks plugin hooks
outright (`/hooks` reports "Hooks Restricted by Policy"). It costs nothing
extra where hooks work: `do_session`/`Invoke-Session` skips re-injecting the
ruleset once `CLAUDE.md` carries it.

The section ends with a line telling the orchestrating session to paste it into
every subagent prompt, because a subagent never reads `CLAUDE.md` on its own.
Where `SubagentStart` also fires that is the ruleset twice, about 30 lines per
subagent. There is no reliable way to detect hook-liveness and skip one, so
this is accepted.

If the user turned the section off, the script leaves it off.

### A5 — Report

- What you created, as a file list, and what the A4 stamp did.
- The A2b summary line: what was routed from existing markdown, and where.
- `CLAUDE.md` line count.
- If you adopted existing content, the table from Mode B phase 2 showing what
  moved where.
- Anything you found during the survey that looked like a pitfall but that you
  could not confirm, so the user can verify it.

Tell the user to restart the session and run `/context` for a baseline number.

---

