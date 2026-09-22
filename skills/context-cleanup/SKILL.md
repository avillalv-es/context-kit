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
reword what is already there. Then do A4b (append the ruleset stub), the same
in both modes.

### 0.3 — Report, in one line

```
context layout bootstrapped: <files created>. For a full survey, run /context-init.
```

Do not survey the repo. Do not propose moves. Do not classify anything. That is
Mode A, and it is the user's call to run it.

---

## Mode A and Mode B

The two survey modes live in their own files, because a run only ever takes
one of them and the other is pure weight on the invocation:

- **Mode A: Initialize** — read `references/mode-a-initialize.md`.
- **Mode B: Cleanup** — read `references/mode-b-cleanup.md`.

Read the one you announced. Do not read both.

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
