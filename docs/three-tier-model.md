# The three-tier model

## The problem

An agent's context window is a budget, and `CLAUDE.md` spends it before you
have typed anything. Whatever is in that file is paid for on every session,
every compaction, and every subagent you spawn — including the ones whose work
has nothing to do with it.

That alone would argue for keeping it short. The sharper problem is that a long
instruction file does not degrade gracefully. As it grows, adherence to *all*
of it drops. Adding a line does not just cost tokens; it makes the lines
already there less likely to be followed. A `CLAUDE.md` that has accumulated
for six months can be actively worse than a short one, because the rules that
actually matter are now buried among the ones that do not.

So the goal is not "write down everything important." It is **place every piece
of knowledge in the cheapest tier that still guarantees it gets used.**

## The tiers

### Tier 1 — `CLAUDE.md`

Loads on every session, unconditionally. Nothing else in the layout has that
guarantee, which is exactly why it should hold almost nothing.

What earns a place:

- **Routing.** Where knowledge lives, and the *condition* for reading it.
- **Commands.** Build, test, lint, run — verified against the actual manifest.
- **Cross-cutting pitfalls.** Things that produce a wrong answer on tasks that
  are not about them.

Tier 1 is written in **router form**: it names where knowledge lives and when
to go there. It does not contain the knowledge.

Cap it. A hard number — 200 lines is a reasonable default — turns "should this
go in?" from a matter of taste into a matter of budget, and forces something
out when something new goes in.

### Tier 2 — `.claude/rules/*.md`

Loads only when a file matching its `paths` frontmatter is touched. This is
where most real conventions belong: they are genuinely important, and they are
genuinely irrelevant most of the time.

```yaml
---
description: What this covers, in one line, written as a trigger.
paths:
  - "src/api/**"
  - "src/schema.sql"
---
```

Scope `paths` as narrowly as the knowledge actually applies. A bare `**/*` is
tier 1 wearing a costume — it loads unconditionally while looking like it does
not, which is the worst of both.

**The one real caveat:** path-scoped rules do not survive compaction until
something re-triggers them. During a long autonomous run, a rule can load at
hour one and be gone by hour three. If a rule would be an *incident* rather
than an annoyance if ignored once, promote it to tier 1 — or better, make it a
hook, which costs no context at all until it fires.

### Tier 3 — `knowledge/` and `.claude/skills/`

Loads only when looked up or invoked. Two shapes:

- **`knowledge/<topic>.md`** — reference and narrative. One topic per file,
  named for the words someone would actually search for. The filename and the
  folder structure *are* the retrieval index; if you cannot find a topic by its
  name, the name is wrong. Every file gets a line in `knowledge/INDEX.md`.
- **`.claude/skills/<name>/SKILL.md`** — a procedure that repeats. The
  `description` must enumerate the situations and vocabulary that will appear
  in a real request, because that string is the entire trigger mechanism.

### Not a tier — delete

Directory trees, dependency lists, file inventories, architecture summaries,
project history. All derivable by looking at the repo. Carrying them anywhere
means maintaining a second copy that will drift from the first, and the drift
is invisible until it causes a wrong decision.

This is the bucket people resist most, because the summaries feel useful. They
are useful — to a human skimming. An agent with file access does not need them
and is harmed by the stale ones.

## The classification test

> If I never saw this, would I get something wrong on a task that has nothing
> to do with this knowledge's subject?

That phrasing does real work. "Is this important?" gets you a yes on
everything. "Would missing it break an *unrelated* task?" is the question tier
1 actually answers.

## Why ties break downward

The two error directions do not cost the same.

| Mistake | Cost |
|---|---|
| Put in tier 2, belonged in tier 1 | One visible mistake, once. You see it, you correct it, you promote the rule. |
| Put in tier 1, belonged in tier 2 | Invisible drag on every session forever. Nothing ever surfaces it. |

The first failure announces itself and is cheap. The second never announces
itself and compounds. So when genuinely undecided, go lower — and **mark the
tie-break**, so it can be revisited when the visible failure shows up.

This is also why "when in doubt, put it in `CLAUDE.md`" is exactly backwards,
despite being the intuitive default.

## Where hooks sit

Hooks are not a tier. They are the escape hatch from the whole model.

A tier is a place to put knowledge so that Claude *reads* it and, hopefully,
acts on it. A hook does not ask — it runs. That makes it the right answer for
anything where being ignored once is an incident rather than an annoyance, and
it is why `docs/authoring.md` says that anything you find yourself restating in
three tiers is really a hook.

There is one trap worth naming, because it looks like a free lunch.

**A `SessionStart` hook that injects context costs exactly what the same text
would cost in `CLAUDE.md`.** The `additionalContext` it returns is loaded into
the session like any other standing instruction, on every session and every
subagent. Moving a paragraph out of `CLAUDE.md` and into a hook does not make
it cheaper; it only makes it ship with a plugin instead of with the repo.

So the rule for hooks mirrors the rule for tier 1:

- **Hooks that run and produce no output are free.** A `PostToolUse` hook that
  appends a line to a ledger, a check that blocks a bad command — these cost
  nothing in context until something goes wrong.
- **Hooks that inject text are tier 1 wearing a different hat.** Subject to the
  same line budget and the same classification test. context-kit's own injected
  ruleset is about thirty lines for exactly this reason; the rest of it lives
  in `skills/lean-execution/`, which loads only when invoked.

The honest summary: use a hook for a *guarantee*, and a tier for *knowledge*.
Injecting knowledge from a hook gets you the cost of tier 1 with the
discoverability of tier 3, which is the worst of both.

## Record the why, not the what

Across all three tiers, the content that earns its place is **rationale**:
decisions that look like bugs to someone who does not know the history,
conventions that differ from the tool's default, constraints that came from
outside the code.

A line that says what the code does is redundant with the code. A line that
says why the code does something surprising is the only place that information
exists.
