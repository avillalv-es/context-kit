---
name: blast-radius
description: Use when the user asks what breaks if something changes, what depends on a file or function, what the impact or blast radius of a change is, or what else needs updating; before renaming, deleting, moving or changing the signature of anything shared; before committing a structural change; when reviewing a diff to find what it affects beyond the files it edits; and when the user runs /blast-radius. Do not use to find where something is defined - grep is faster and never stale.
---

# Blast radius

Grep finds where a name appears. Only the import graph walked *backwards* says
what depends on it, two and three files out. The script lists the importers;
it cannot tell you whether each one breaks. **Reading them is your job, and it
is the point of this skill.** A list you did not open proves nothing.

## Procedure

1. **Pick the mode.**

   | About to... | Run |
   |---|---|
   | change, rename or delete one function, type or constant | `<symbol>`; add `--file <path>` when several files define that name |
   | move, split, rename or delete a file | `--file <path>` |
   | review or finish a change that is already made | `--diff`; `--diff --base main` for a whole branch |

2. **Run it:** `sh "${CLAUDE_PLUGIN_ROOT}/scripts/blast-radius.sh" <mode and arguments>`.
   Options: `--depth N` (3), `--max N` rows per depth (40), `--cached` to skip
   the graph rebuild. It rebuilds by default: a stale graph is worse than none.
3. **Read the first line:** `blast-radius: seeds= affected= depth= edges= gaps=`.
   `edges=0` means the graph is empty, not that nothing depends on the seed.
   `gaps` above 0 means open `## Blind spots` before trusting the list.
4. **Open every `## Depth 1` importer**, at its import line and at each use of
   the names being changed. Give each a verdict:
   - `breaks`: it will fail to compile, type-check or run as it stands
   - `must-update`: it still works but has to change with this (a re-export, a copy of the type, a doc)
   - `safe`: it only uses what stays the same
   - `unclear`: say what you could not tell

   With more than about 8 depth-1 importers, hand the reading to one subagent
   (`model: "sonnet"`): give it the change, the importer list and these four
   verdicts, and ask for a table of `file:line | verdict | one-line reason`.
   Check the `breaks` and `unclear` rows yourself.
5. **Follow depth 2 and beyond only through re-exports.** An importer that just
   re-exports (a barrel, `index.ts`, `__init__.py`) passes the break on: read
   *its* importers. Anything else past depth 1 is context.
6. **Grep for runtime wiring** the graph cannot see: DI registration, route
   tables, config keys, string lookups, reflection, templates, migrations.
   `git grep -n -w <name>` in the repo, config and docs included.
7. **Run `## Tests to run`** with the repo's own test command (see CLAUDE.md).
   If CLAUDE.md says development is Docker-only, run them through `docker compose`.
   If you cannot run them, say so; do not call the change safe.
8. **Report:** the stats line, the verdict table, the tests run and how they
   went, and one line of caveat. Do not paste the raw report back.
9. **After editing, before committing, run `--diff` again.** What you changed is
   not always what you planned, and `--diff` also seeds deleted and renamed files.

## What the report holds

The first line is always the stats line. Then `##` sections, each printed only
when non-empty (Seeds always): `Seeds`, `Depth 1`, `Depth 2`..., `Name matches`,
`Tests to run`, `Blind spots`. A row is `path:line -> via`: that file imports
`via` at that line. `[inferred import, verify]` means the edge came from an
alias or suffix match rather than a literal path; open it. In symbol mode, rows
are followed by the lines where the symbol is used.

`Name matches` are files that use the name with no import path to the seed:
usually a different symbol with the same name. `Blind spots` are unresolved
imports next to the seeds, plus "possible missed importers": an import that did
not resolve but names a seed. Read those before concluding nothing else depends on it.

Exit codes: `0` ok or nothing changed; `1` usage error, unknown `--base`, or the
graph could not be built; `2` the symbol appears nowhere.

## What it cannot see

It follows imports between files. It does not know which function calls which,
and it cannot see anything wired at runtime. "Nothing imports the seed" is three
different statements: a real leaf, a runtime-wired module, or an import form
that did not resolve. Say which one you believe, and why. Details and how to
read `Blind spots`: `references/reading-output.md`.
