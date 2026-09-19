# Efficiency

The three-tier model organizes *what Claude knows*. This organizes *how Claude
works*. They are different problems, and the second one is where most tokens
actually go.

Most of this is absorbed from [ponytail](https://github.com/DietrichGebert/ponytail)
(MIT). See [NOTICE](../NOTICE) for exactly what was taken and what was changed.

---

## Where the tokens actually go

Four places, in rough order of size:

1. **Reading more than you needed.** A whole file pulled in to find one
   function. A directory listing that could have been a glob.
2. **Writing more than you needed.** A class where a function would do; a
   dependency where a stdlib call would do.
3. **Explaining more than you needed.** Prose defending a decision nobody
   questioned.
4. **Standing context.** Everything in `CLAUDE.md` and every always-on ruleset,
   paid on every session and every subagent, forever.

The three-tier model attacks (4). This document attacks (1) through (3).

Note that (4) is why the injected ruleset is short. A `SessionStart` hook's
`additionalContext` costs exactly what the same text would cost in `CLAUDE.md`
— injection is not free, and anyone who tells you it saves tokens has
confused *where the text lives* with *whether it is loaded*. The hook earns its
place because it ships with the plugin and reaches repos with no `CLAUDE.md`,
not because it is cheaper.

---

## The ladder

Stop at the first rung that holds.

1. Does this need to exist at all? (YAGNI)
2. Already in this codebase? Reuse it.
3. Standard library does it? Use it.
4. Native platform feature covers it? Use it.
5. Already-installed dependency solves it? Use it.
6. Can it be one line? One line.
7. Only then: the minimum that works.

Rung 4 has a lookup table: [`knowledge/platform-native.md`](../knowledge/platform-native.md).
Roughly 180 rows mapping "the package you were about to install" to "the thing
the platform already ships", across HTML, CSS, browser APIs, SwiftUI, Node,
Python, SQL, .NET and the pandas/Polars/DuckDB stack. Checking one file is
cheaper than searching, and much cheaper than guessing.

**The ladder runs after you understand the problem, not instead of it.** This
is the qualifier that keeps the whole thing from being harmful. Laziness that
skips comprehension to ship a small diff dresses up as efficiency and ships a
confident wrong fix. The smallest change in the wrong place is not lazy, it is
a second bug.

---

## Reading discipline

The part ponytail does not have, and the largest single input lever.

- **Locate before you read.** Grep or Glob for the symbol, then read the ranges
  around the hits. Reading a file whole to find one definition is the most
  common waste in a long session.
- **Delegate fan-out.** A search spanning many files or naming conventions goes
  to a subagent. The raw tool output lands in its window; only the conclusion
  comes back to yours. This is the one case where spending more total tokens
  buys a materially longer main-window session.
- **The bar is isolatable AND verbose.** Specialization alone is not a reason.
  A three-file search costs more to delegate than to do.
- **Do not re-read what you just edited.** The edit tools error on failure. A
  confirming read buys nothing.

---

## Output discipline

Answer first. Then at most three short lines: what you skipped, when to add it.

> If the explanation is longer than the code, delete the explanation.

Every paragraph defending a simplification is complexity smuggled back in as
prose.

**The exemption matters as much as the rule.** Explanation the user asked for —
a report, a walkthrough, per-phase notes, a plan — is not debt. Give it in
full. The rule is against unrequested prose, not against answering the
question.

---

## What is never simplified away

Input validation at trust boundaries. Error handling that prevents data loss.
Security. Accessibility. Anything explicitly requested.

And: **lean code without its check is unfinished.** Non-trivial logic leaves
one runnable check behind — the smallest thing that fails if the logic breaks.
No frameworks, no fixtures. Trivial one-liners need no test; YAGNI applies to
tests too.

---

## The `shortcut:` marker

A deliberate simplification with a known ceiling gets a comment naming the
ceiling and the upgrade trigger:

```python
# shortcut: global lock, per-account locks if throughput matters
```

`/shortcut-ledger` harvests them with one grep. A marker with no upgrade
trigger gets a `no-trigger` tag, because those are the ones that quietly become
permanent.

The prefix is `shortcut:`, not `ponytail:`. Scattering a third-party plugin's
name through your source is a poor trade for a convention that reads fine
without it.

---

## Levels

| Level | What changes |
|---|---|
| `lite` | Build what is asked, then name the leaner option in one line. |
| `full` | The ladder enforced. Shortest working diff, shortest explanation. Default. |
| `ultra` | Deletion before addition. Ship the one-liner and challenge the requirement. |
| `off` | Nothing injected. |

`/lean <level>` persists across sessions. `CONTEXT_KIT_LEVEL` overrides for one
session. `CONTEXT_KIT_OFF=1` disables every context-kit hook.

`ultra` is a poor default for exploratory data work, where the "unnecessary"
intermediate is often the analysis. `lite` is a good default for a codebase you
do not know yet.

---

## Never invent a savings number

Do not tell anyone how many lines or tokens they saved on their repo. The
version that was not built was never written, so there is no baseline to
subtract from. A fabricated percentage is worse than no number, because it
gets quoted.

Two real numbers exist:

- `/context` — the actual context-window measurement, before and after.
- `/shortcut-ledger` — a counted list of real markers.

Use those.
