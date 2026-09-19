# Anti-patterns

Failure modes, what they look like in the wild, and the fix.

---

## The file that only grows

**Looks like:** `CLAUDE.md` at 400 lines, most of it added one line at a time
after individual sessions. Nobody can say which lines still matter.

**Why it happens:** adding is free and local; removing requires knowing whether
anyone depends on it. So the ratchet only turns one way.

**Fix:** a hard line cap, plus the "do not add on your own initiative" clause
in the stub. The cap converts every addition into a trade.

---

## Location instead of trigger

**Looks like:** `Chart mechanics are in knowledge/charts.md`.

**Why it fails:** it is a true statement about the repo, not an instruction.
Nothing about it says when to act, so it never fires.

**Fix:** `Read knowledge/charts.md before modifying any chart config.` Every
pointer in tier 1 states its reading condition.

---

## The rule with no `paths`

**Looks like:** a file in `.claude/rules/` with no `paths` frontmatter, or with
`paths: ["**/*"]`.

**Why it fails:** it loads unconditionally. It is tier 1 wearing a costume —
full cost, while sitting in the folder that implies it is cheap. Worse, it is
excluded from the tier-1 line cap, so it is invisible to the one mechanism that
would have caught it.

**Fix:** scope it, or move it into `CLAUDE.md` honestly and let it compete for
space like everything else.

---

## The capability description

**Looks like:** a skill described as `Helps with database migrations.`

**Why it fails:** the description is the whole trigger mechanism. A statement of
capability matches nothing a user would actually type.

**Fix:** enumerate situations and real vocabulary. `Use when adding, editing or
reverting a migration, when a migration fails to apply, or when the user asks
about schema drift.`

---

## The stale number

**Looks like:** `CLAUDE.md` says the suite has 12 tests. It has 28. Two
sessions have now reasoned from 12 — one of them concluded coverage was thin
and wrote tests that already existed.

**Why it is the worst one:** every other anti-pattern here produces *inaction*.
This one produces confident wrong action, and it is asserted on every task
until a human happens to notice.

**Fix, in order of preference:**

1. Do not carry the number. Carry the command that produces it.
2. If you must carry it, carry its provenance and an instruction to
   re-measure: `409 passed. **Re-measure before quoting this.**`
3. Best: a hook or a test that fails when the documented number and the real
   one disagree. A guarantee costs no context until it fires; a request costs
   context every session and can still be ignored.

The general principle: **anything that can go stale silently should be checked
mechanically, not asserted in prose.**

---

## The architecture summary

**Looks like:** a directory tree, a module table, or a "how it all fits
together" section in `CLAUDE.md`.

**Why it fails:** it is derivable, so it is redundant on the day it is written
and wrong some weeks later. Nothing tells you which week.

**Fix:** delete it. If someone genuinely needs a map, generate one on demand
rather than carrying one. The map that is regenerated is never stale; the one
that is stored always eventually is.

**The honest cost of this:** you give up having an at-a-glance overview, and
that is a real loss for human onboarding. Put it in `README.md`, where humans
read it and where its staleness is visible to reviewers — not in the file that
gets asserted to an agent on every task.

---

## Rules grouped by session

**Looks like:** `.claude/rules/` holding `auth-work.md`, `auth-followup.md`,
`auth-fixes-oct.md`.

**Why it fails:** three files load for the same trigger, they overlap, and they
will eventually contradict each other. The one that wins is whichever the model
read last.

**Fix:** merge by domain. Before creating a rule, look for the existing one
that covers the area.

---

## Tier 1 as the safe default

**Looks like:** "I am not sure where this goes, so I will put it in `CLAUDE.md`
to be safe."

**Why it fails:** it is backwards. The tier-1 mistake is the one that never
surfaces. The tier-2 mistake surfaces once, visibly, and you fix it.

**Fix:** break ties downward and mark them, so the visible failure — when it
comes — tells you which tie-break to revisit.

---

## Findings that live only in chat

**Looks like:** a two-hour investigation, a clear conclusion, and then a
compaction. The conclusion survives as one summarized sentence; the evidence
does not.

**Why it fails:** the specifics are exactly what you would have to re-derive,
and they are the first thing a summary drops.

**Fix:** append to `findings/<investigation>.md` as you go, not at the end. A
finding written after the compaction is a finding written from memory.

---

## Resolving an open question inside an implementation

**Looks like:** a requirement is genuinely undecided. An implementation picks a
reasonable answer and ships. Now the answer is in the code, nobody agreed to
it, and the fact that it was ever open is gone.

**Why it fails:** the silence *was* the finding. Erasing it destroys the signal
that someone needed to make a decision.

**Fix:** write the question into the record first, then implement against the
recorded answer — or implement the part that does not depend on it and say
explicitly what you left out. A register of open questions is worth maintaining
precisely because it makes absence legible.
