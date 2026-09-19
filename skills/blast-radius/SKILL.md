---
name: blast-radius
description: Use when the user asks what breaks if something changes, what depends on a file or function, what the impact or blast radius of a change is, what else needs updating, or what a refactor will touch; when auditing or debugging and you need to know which files are downstream of a change; before renaming, deleting, or changing the signature of anything shared; and when reviewing a diff to find what it affects beyond the files it edits. Also use when the user runs /blast-radius. Do not use to find where something is defined - grep is faster and never stale.
---

# Blast radius

What depends on the thing about to change.

Grep answers "where does this name appear". It cannot answer "what breaks",
because that needs the import graph walked *backwards*, two and three files
out, through re-exports and barrel files. That is the one question a plain
search structurally cannot answer, and it is the whole reason this exists.

## Run it

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/blast-radius.sh" <symbol>
sh "${CLAUDE_PLUGIN_ROOT}/scripts/blast-radius.sh" --file src/lib/auth.ts
sh "${CLAUDE_PLUGIN_ROOT}/scripts/blast-radius.sh" --diff
sh "${CLAUDE_PLUGIN_ROOT}/scripts/blast-radius.sh" --diff --base main
```

`--depth N` (default 3), `--max N` rows per depth, `--cached` to reuse the
existing graph instead of rebuilding.

It rebuilds the import graph every run by default. That is deliberate: this
tool's only value is being right, and a cached graph silently describing
yesterday's imports is worse than no graph. Use `--cached` only in a tight
loop where you know nothing moved.

## Which mode

| Situation | Mode |
|---|---|
| auditing or debugging a change you already made | `--diff` — start here |
| reviewing a branch | `--diff --base <branch>` |
| about to rename, delete, or change a signature | the bare symbol |
| about to move or split a file | `--file` |

`--diff` is the one to reach for during an audit. It seeds from every changed
file at once — unstaged, staged and untracked — so the answer is "here is
everything downstream of this change", not one symbol at a time.

## Reading the output

Rows are grouped by depth. Depth 1 imports a seed directly; depth 2 imports
something at depth 1. **Depth 1 is where breakage is near-certain; by depth 3
you are looking at things that merely sit downstream.** Read outward and stop
when it stops being plausible.

Three things in the report need care:

**`[inferred import, verify]`.** The edge came from a path alias, a baseUrl
specifier or a unique-suffix match rather than a literal relative path. It is
usually right. Open the file before acting on it.

**Name matches.** In symbol mode the report separately lists files where the
name appears but no import connects them to the seed. Those are *usually a
different symbol with the same name*. Never treat that section as part of the
blast radius without reading each one.

**Blind spots.** The count of imports that did not resolve. Read it. A high
number in the area you are changing means the walk is incomplete there, and
you should fall back to grep for that part.

## What it cannot see, and what to do about it

It is file-level: it follows imports, so it knows which file depends on which
file. It does not know which *function* calls which function, and it cannot
see anything wired at runtime:

- a route table or URL map
- a dependency-injection container
- a plugin or handler registry keyed by string
- reflection, `getattr`, dynamic `require` of a computed path
- templates, config files and migrations that name a symbol in text

So: **treat the result as a strong starting set, never a complete one.** When
the thing you are changing is registered rather than imported — a handler, a
serializer, a migration, a CLI subcommand — run a plain grep for its name as
well, and say in your answer that you did both.

If the report says nothing imports the seed, that is three different
statements — a genuine leaf, a runtime-wired module, or a resolution gap.
The report distinguishes them. Pass that distinction on rather than reporting
"nothing depends on it".

## Reporting

Lead with the count and the depth-1 list, because that is what the user acts
on. Then anything at depth 2+ that looks genuinely at risk. Then the caveats,
in one line, not a lecture.

Do not paste the whole report back. It is written to be read by you, and
summarized by you.
