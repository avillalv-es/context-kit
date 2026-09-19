---
name: skill-capture
description: Use immediately after finishing a multi-step procedure that would be run again, when the same kind of task has now come up more than once, when a body of project knowledge would be cheaper to look up than to re-derive, or when the session-start hook reports repeated procedures. Also use when the user says capture this, make a skill, turn this into a skill, save this procedure, or runs /skill-capture. Creates the skill without asking first. Do not use for a one-off task, or for anything an existing skill already covers.
---

# Capture a procedure as a skill

You create the skill and report it. You do not ask permission first: a new file
under `.claude/skills/` is additive, uncommitted, and one `git checkout` from
gone. What you must not do is capture the wrong things, so the filters below
are the whole job.

Announce nothing until step 7. A paragraph explaining that you are about to
create a skill costs more than the skill.

---

## 1 — Check it is not already covered

Before writing anything, look:

- `.claude/skills/*/SKILL.md` — read the `description` of each, not the body.
- `knowledge/INDEX.md` — the topic may already be written down.
- The plugin and personal skills already loaded this session.

**Extend before you create.** If an existing skill covers the same subject,
add to it. Five skills that each cover an area beat fifteen that each cover an
afternoon — the same rule tier-2 rules already follow. A near-duplicate skill
is worse than no skill: two descriptions competing for the same trigger means
neither fires reliably.

## 2 — Confirm it is actually a skill

Run the classification test from `context-cleanup`:

> If I never saw this, would I get something wrong on a task that has nothing
> to do with this knowledge's subject?

- **Yes** → it belongs in `CLAUDE.md`, not here. Say so in one line and stop.
- **It applies whenever certain files are touched** → it is a tier-2 rule.
  Write `.claude/rules/<topic>.md` with a narrow `paths` list instead.
- **It is reference or narrative** → it is `knowledge/<topic>.md`, not a skill.
- **It is a procedure that repeats** → continue.
- **It is derivable by reading the codebase** → stop. Do not write it anywhere.

## 3 — Name it

Kebab-case, named for the words someone would search for when they need it.
`deploy-staging`, not `deployment-helper`. The directory name is part of the
retrieval index.

## 4 — Write the description as a trigger

This is the entire firing mechanism. Everything else in the file is inert until
the description matches.

- Weak: `Helps with database migrations.`
- Strong: `Use when adding a column, writing an Alembic revision, or when a
  migration fails to apply. Do not use for read-only schema questions.`

Enumerate the situations and the vocabulary that will appear in a real request.
Then **say when not to fire** — a skill that derails unrelated work is worse
than one that never fires.

## 5 — Keep the body short

Cap it around 100 lines. If the procedure needs heavy reference material —
a schema, a long table, an API surface — put that in `knowledge/<topic>.md` and
link to it. A skill that inlines its own reference recreates the CLAUDE.md
problem one level down: it all loads the moment the skill fires.

Write the steps, the failure modes, and the verification. Not the rationale.

## 6 — Write the files

- `<repo>/.claude/skills/<name>/SKILL.md` — **project-local, always.** Never
  `~/.claude/skills/`. Project-local means it lands in git, gets reviewed, and
  travels with the repo that needs it.
- Add one line to `knowledge/INDEX.md` stating *when to read it*, not just what
  it is. Create `INDEX.md` if it does not exist.

Lowercase `.md`. `SKILL.MD` resolves on Windows and macOS but is invisible on a
case-sensitive filesystem, which is where CI runs.

Make ordinary working-tree edits. **Do not commit.**

## 7 — Report, in one line

```
created: .claude/skills/<name>/SKILL.md - fires on: <the trigger words>
```

Two lines if you also wrote a knowledge file. Nothing else. Then return to what
you were doing.

---

## Never capture

- **A one-off.** Repeatable means you expect it again, not that it took effort.
- **Anything derivable by reading the code.** Directory structure, exports,
  call graphs, dependency lists.
- **Anything an existing skill covers.** Extend it instead.
- **A single command.** If the whole content is `npm run deploy`, it is a line
  in `CLAUDE.md` under Commands, not a skill.
- **Something you cannot state a trigger for.** If you cannot finish the
  sentence "use this when...", there is nothing to capture yet.
- **Secrets, credentials, tokens, or connection strings.** If the procedure
  needs one, write the *name* of the variable and where it comes from.

## When the hook reports repeats

The session-start hook counts repeated shell commands and names any that
crossed the threshold. That is a signal, not an instruction. A command running
three times may be a procedure worth capturing, or it may be `pytest` running
three times because three tests failed. Apply step 2 to each one, capture the
ones that pass, and say nothing about the ones that do not.
