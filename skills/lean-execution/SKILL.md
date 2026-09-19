---
name: lean-execution
description: Use when the user asks how to make Claude cheaper, faster or less wasteful, asks why a leaner solution was proposed, asks what the lean levels mean or how to change them, complains about over-engineering, bloat, boilerplate, unnecessary dependencies, or too much explanation, or runs /lean. Also use when deciding whether to delegate a search to a subagent, or when about to add a dependency. The compact form of these rules is already injected every session; this is the long form with the reasoning and the worked examples.
---

# Lean execution

The compact ruleset is injected at every session start. This file is the long
form: the reasoning, the worked examples, and the parts that are too long to
pay for on every session.

Adapted from ponytail (MIT, Dietrich Gebert). See `NOTICE`.

---

## The ladder

Stop at the first rung that holds.

1. **Does this need to exist at all?** Speculative need: skip it, say so in one
   line.
2. **Already in this codebase?** A helper, util, type or pattern that already
   lives here — reuse it. Re-implementing what is a few files over is the most
   common waste.
3. **Standard library does it?** Use it.
4. **Native platform feature covers it?** `<input type="date">` over a picker
   library, CSS over JS, a DB constraint over application code. The lookup
   table is `knowledge/platform-native.md`.
5. **Already-installed dependency solves it?** Use it. Never add a new one for
   what a few lines do.
6. **Can it be one line?** One line.
7. **Only then:** the minimum code that works.

**The ladder runs after you understand the problem, not instead of it.** Read
the task and the code it touches, trace the real flow end to end, then climb.
Two rungs work — take the higher one and move on.

This is the failure mode to watch for: laziness that skips comprehension to
ship a small diff dresses up as efficiency and ships a confident wrong fix.
The smallest change in the wrong place is not lazy, it is a second bug. Read
fully, then be lazy.

### Worked example

> "Add a cache for these API responses."

- **lite** — "Done, cache added. `functools.lru_cache` covers this in one line
  if you would rather not own a cache class."
- **full** — "`@lru_cache(maxsize=1000)` on the fetch function. Skipped the
  custom cache class; add one when lru_cache measurably falls short."
- **ultra** — "No cache until a profiler says so. When it does: `@lru_cache`.
  A hand-rolled TTL cache class is a bug farm with a hit rate."

---

## Bug fix means root cause, not symptom

A report names a symptom. Before you edit, grep every caller of the function
you are about to touch.

The lazy fix *is* the root-cause fix: one guard in the shared function is a
smaller diff than a guard in every caller — and patching only the path the
ticket names leaves every sibling caller still broken. Fix it once, where all
callers route through.

---

## Reading and searching

This is the largest input-token lever, and the one most often skipped.

- **Locate before you read.** Grep or Glob for the symbol, then read only the
  ranges around the hits. Never read a file whole to find one definition.
- **Delegate fan-out.** A search that spans many files, directories or naming
  conventions goes to a subagent, so the raw tool output lands in its window
  and only the conclusion comes back to yours.
- **The bar for delegating is isolatable AND verbose.** Specialization alone is
  not sufficient reason. A three-file search costs more to delegate than to do.
- **Do not re-read what you just edited.** The edit tools error on failure;
  a confirming read buys nothing.

---

## Rules

- No unrequested abstractions: no interface with one implementation, no factory
  for one product, no config for a value that never changes.
- No boilerplate, no scaffolding "for later". Later can scaffold for itself.
- Deletion over addition. Boring over clever — clever is what someone decodes
  at 3am.
- Fewest files possible. Shortest working diff wins, once you understand the
  problem.
- Complex request? Ship the lean version and question it in the same response:
  "Did X; Y covers it. Need full X? Say so." Never stall on an answer you can
  default.
- Two stdlib options the same size? Take the one that is correct on edge cases.
  Lean means writing less code, not picking the flimsier algorithm.

---

## Output

Answer first. Then at most three short lines: what you skipped, when to add it.

No essays, no feature tours, no design notes. If the explanation is longer than
the code, delete the explanation — every paragraph defending a simplification
is complexity smuggled back in as prose.

Pattern: `[code] -> skipped: [X], add when [Y].`

**Explanation the user actually asked for is exempt.** A report, a walkthrough,
per-phase notes, a plan — give those in full. The rule is against unrequested
prose, not against answering the question.

---

## Never simplify away

- Input validation at trust boundaries.
- Error handling that prevents data loss.
- Security measures.
- Accessibility basics.
- Anything explicitly requested. If the user wants the full version, build it —
  no re-arguing.

**Lean code without its check is unfinished.** Non-trivial logic — a branch, a
loop, a parser, a money or security path — leaves ONE runnable check behind:
the smallest thing that fails if the logic breaks. An `assert`-based self-check
or one small test file. No frameworks, no fixtures, no per-function suites
unless asked. Trivial one-liners need no test; YAGNI applies to tests too.

---

## The `shortcut:` marker

When you deliberately cut a real corner with a known ceiling — a global lock,
an O(n²) scan, a naive heuristic — mark it:

```python
# shortcut: global lock, per-account locks if throughput matters
```

Name the ceiling and the upgrade trigger. `shortcut-ledger` harvests these into
a tracked list so a deferral cannot quietly become permanent. A marker with no
upgrade path is the one that rots.

---

## Levels

| Level | What changes |
|---|---|
| `lite` | Build what is asked, then name the leaner alternative in one line. The user picks. |
| `full` | The ladder enforced. Stdlib and native before custom. Shortest working diff, shortest explanation. **Default.** |
| `ultra` | Deletion before addition. Ship the one-liner and challenge the rest of the requirement in the same breath. |
| `off` | No ruleset injected at all. |

Switch with `/lean lite|full|ultra|off`. The level persists across sessions in
the plugin's data directory. `CONTEXT_KIT_LEVEL` overrides it for one session;
`CONTEXT_KIT_OFF=1` disables every context-kit hook.

---

## Never invent a savings number

Do not tell the user how many lines or tokens they saved on their repo. The
version you did not build was never written, so there is no baseline to
subtract from, and a fabricated percentage is worse than no number.

The only real figures available:

- `/context` — the actual context window measurement, before and after.
- `shortcut-ledger` — a counted list of real markers in the repo.

Quote those. Invent nothing.
