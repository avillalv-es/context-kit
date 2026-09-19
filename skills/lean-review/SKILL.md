---
name: lean-review
description: Use when the user asks to review for over-engineering, asks what can be deleted or cut, asks whether something is over-engineered, asks to find bloat or dead code, wants a simplify review, wants to audit a codebase for complexity, or runs /lean-review. Reviews the current diff by default; pass --repo to scan the whole tree. Lists findings only, never applies them. Do not use for correctness bugs, security holes, or performance work - those route to a normal review pass.
---

# Lean review

Hunt unnecessary complexity and report what to cut. One line per finding. The
best outcome for a diff is getting shorter.

Adapted from ponytail-review and ponytail-audit (MIT, Dietrich Gebert). See
`NOTICE`.

## Scope

- **Default: the current diff.** `git diff` for unstaged, `git diff --staged`,
  or `git diff <base>...HEAD` for a branch. Ask which only if it is ambiguous.
- **`--repo`: the whole tree.** Rank findings biggest cut first, and use the
  hunt list below to narrow the search rather than reading everything.

## Tags

- `delete:` dead code, unused flexibility, speculative feature. Replacement: nothing.
- `stdlib:` hand-rolled thing the standard library ships. Name the function.
- `native:` dependency or code doing what the platform already does. Name the feature.
- `yagni:` abstraction with one implementation, config nobody sets, layer with one caller.
- `shrink:` same logic, fewer lines. Show the shorter form.

## Format

`<file>:L<line>: <tag> <what>. <replacement>.`

Drop the filename for a single-file diff. For `--repo`, put the path last:
`<tag> <what to cut>. <replacement>. [path]`

## Examples

Not this:

> "This EmailValidator class might be more complex than necessary — have you
> considered whether all these validation rules are needed at this stage?"

This:

```
L12-38: stdlib: 27-line validator class. "@" in the string, 1 line; real validation is the confirmation mail.
L4: native: moment.js imported for one format call. Intl.DateTimeFormat, 0 deps.
repo.py:L88: yagni: AbstractRepository with one implementation. Inline it until a second one exists.
L52-71: delete: retry wrapper around an idempotent local call. Nothing replaces it.
L30-44: shrink: manual loop builds a dict. dict(zip(keys, values)), 1 line.
```

## Hunt list (for `--repo`)

Dependencies the stdlib or platform already ships. Single-implementation
interfaces. Factories with one product. Wrappers that only delegate. Files
exporting one thing. Dead flags and config nobody sets. Hand-rolled stdlib.

Check candidate dependencies against `knowledge/platform-native.md` before
flagging — it already maps the common ones.

## Scoring

End with the only metric that matters:

- Diff: `net: -<N> lines possible.`
- `--repo`: `net: -<N> lines, -<M> deps possible.`

Nothing to cut: `Lean already. Ship.` and stop.

## Boundaries

**Scope is over-engineering and complexity only.** Correctness bugs, security
holes and performance are explicitly out of scope — route them to a normal
review pass, not this one.

A single smoke test or `assert`-based self-check is the lean minimum, not
bloat. Never flag it for deletion.

Lists findings. Applies nothing. If the user wants the cuts made, they will say
so, and that is a separate pass.
