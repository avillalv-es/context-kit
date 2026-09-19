# Authoring standards

How to write each tier so it actually fires. Most context layouts fail not
because the knowledge is wrong but because it is phrased in a way that never
triggers.

---

## Tier 1 — `CLAUDE.md`

**Router form.** Name where knowledge lives and the condition for reading it.
Do not inline the knowledge itself.

**Write the trigger, not the location.** This is the single highest-leverage
rule in this document.

- Inert: `Chart mechanics are in knowledge/charts.md`
- Live: `Read knowledge/charts.md before modifying any chart config`

The first is a fact about the repo. The second is an instruction with a
condition attached, and only the second changes behavior.

**Sections worth having**, omitting any with no real content:

- **Commands** — verified against the manifest, not assumed. If you have not
  run it, do not write it.
- **Conventions** — only where they differ from the tool's default or from
  what a competent developer would guess. Matching the default? Leave it out.
- **Pitfalls** — things with a non-obvious failure mode. Highest value section;
  weight your survey toward finding these.
- **Where knowledge lives** — the router.

**Never include:** directory trees, dependency lists, architecture overviews,
project history, or anything derivable by looking.

**Numbers are a liability.** Test counts, file counts, version numbers and
ports in tier 1 get asserted on every task until someone notices they are
wrong — and by then decisions have been made on top of them. If you must carry
a number, say where it came from and when, so a reader knows to re-measure:

> `pytest` — 409 passed. **Re-measure before quoting this.**

---

## Tier 2 — `.claude/rules/*.md`

**Scope `paths` narrowly.** As narrow as the knowledge genuinely applies. Never
a bare `**/*` — that is tier 1 in disguise, paying the full cost while looking
cheap.

**Group by domain, not by session.** The rule belongs with the subject, not
with whatever task happened to produce it. Before creating a sibling file, look
for an existing rule that covers the same area and add to it. Five rules that
each cover an area beat fifteen that each cover an afternoon.

**Name the authority.** A rule that says what to do is fine. A rule that says
what to do *and where that was decided* survives disagreement:

> Authority: `docs/conventions.md` §3–§6. If you need to break one of these,
> change the doc in the same commit and say why.

That last clause matters. It gives a legitimate path to deviate, which is what
stops a rule from being quietly ignored the first time it is inconvenient.

**Prefer enforceable rules.** If a rule is checkable by grep, say so and say
how. If it is checkable by a hook or a test, it probably should not be a rule
at all — see below.

**Promote if load-bearing.** Rules do not survive compaction until re-triggered.
If ignoring this rule once would be an incident rather than an annoyance, it
belongs in tier 1 or in a hook, even though it is technically file-scoped.

---

## Tier 3a — `knowledge/*.md`

**One topic per file.** Named for the words someone would search for. The
filename is the retrieval index.

**Index everything.** Each file gets a line in `knowledge/INDEX.md` stating
*when to read it*, not just what it is. Same trigger-not-location rule as tier
1.

**Split past ~300 lines.** A lookup pulls the whole file. A 900-line knowledge
file means every question about one of its subtopics drags in the other eight.

**Point at what already exists.** If the real reference lives in `docs/` or in
a per-folder `README.md`, the index should point *there* rather than copying
it. One place to look, one place to update.

---

## Tier 3b — `.claude/skills/*/SKILL.md`

**The `description` is the entire trigger.** Everything else in the file is
inert until the description matches. Write it as a list of situations and the
vocabulary that will appear in a real request — not as a statement of what the
skill can do.

- Weak: `Helps with context management.`
- Strong: `Use when the user runs /context-init, or asks to set up, initialize,
  clean up, tier, audit, reorganize, or trim the context layout or CLAUDE.md.`

The second enumerates real trigger words. The first matches nothing.

**Say when *not* to fire.** A skill that fires during unrelated work is worse
than one that never fires, because it derails tasks that were going fine.
`Explicit invocation only. Never invoke this during an unrelated task.` is a
sentence worth its length.

**Lowercase `.md`.** `SKILL.MD` is invisible on a case-sensitive filesystem.

---

## Commands

The filename becomes the command name: `commands/context-init.md` gives
`/context-init`. Frontmatter carries a one-line `description` for the picker.

Keep commands thin. A command should decide *which* mode or path to take and
then hand off to a skill; the procedure itself belongs in the skill, where it
is reusable and where it is not reloaded every time the command list renders.
`$ARGUMENTS` passes the rest of the user's line through.

---

## When it should not be knowledge at all

Three escape hatches worth proposing rather than writing another rule:

- **A hook**, when a rule would be an incident rather than an annoyance if
  ignored once. Hooks cost zero context until they fire, so a guarantee is
  strictly cheaper than a request. Anything you find yourself restating in
  three tiers is a hook.
- **A subagent**, when work is genuinely isolatable *and* verbose enough to
  dump large tool output into the main window. Specialization alone is not
  sufficient reason. A real proposal needs a trigger-condition description, a
  `skills` list preloading only its own domain, and a return contract stating
  exactly what comes back.
- **A test**, when the rule is about code and can be asserted. A failing test
  is a better rule than a paragraph.

---

## Throughout

- **Record the why, not the what.** Rationale, pitfalls, and conventions that
  differ from defaults earn their place. Anything derivable does not.
- **Preserve wording when moving a line.** Relocating knowledge is not an
  invitation to rewrite it. The original phrasing usually encodes a distinction
  the rewrite loses.
- **Never delete something you cannot classify.** Flag it and ask.
