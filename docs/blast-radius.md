# Blast radius

`/blast-radius` answers one question: **what breaks if this changes.**

Grep answers "where does this name appear". That is a different question, and
for the common cases grep answers it better — instantly, and never stale. The
one thing grep structurally cannot do is walk the import graph *backwards*,
two and three files out, through re-exports and barrel files, to find what
depends on the thing you are about to touch. That is what this is for, and it
is the only reason it exists.

---

## The trade being made

There are two ways to build this, and they are not close in cost.

| | Symbol-level (what Graphify does) | File-level (what this does) |
|---|---|---|
| Parses with | tree-sitter, one grammar per language | line patterns, comment- and string-aware |
| Answers | which function calls which function | which file depends on which file |
| Needs | ~40 grammars, per-language resolvers, a cache, a daemon, a git merge driver | nothing |
| Goes stale when | any function body changes | an import line changes |
| Fails on | dynamic dispatch, DI, reflection, monkeypatching | the same, plus intra-file detail |

The second column is roughly 15% of the work for most of the value, and it
degrades far more slowly, because imports change much less often than the
code between them. It is also the part grep genuinely cannot replace.

What was given up is real: this does not know that `formatDate` is called on
line 88 of a file that imports the module. It knows the file depends on the
module. For a blast radius that is usually the right granularity anyway —
you are going to open the file regardless.

## Modes

```bash
/blast-radius                        # no argument: everything changed in the working tree
/blast-radius --diff --base main     # everything changed since branching from main
/blast-radius verifySignature        # a symbol
/blast-radius verifySignature --file src/lib/auth.ts  # ...as defined in that file
/blast-radius src/lib/auth.ts        # a path means --file
```

`--diff` is the one for audits and debugging. It seeds from every changed
file at once, so the answer is "here is everything downstream of this change".
It covers:

- **unstaged, staged and untracked** work. A new file is the most common thing
  an audit adds, and `git diff` alone never mentions it.
- **deleted files and the old path of a rename**, tagged `[deleted]` and
  `[renamed to ...]`. Deleting or moving is exactly when importers break, so
  those paths stay seeds. Their imports no longer resolve in the work tree, so
  the extractor is handed the paths as extra members of the file set (never
  scanned) and the graph is built in a scratch directory, leaving the shared
  graph free of edges to files that are gone.
- **`--base REF`** diffs from the merge-base of `REF` and `HEAD`, so it includes
  the branch's commits *and* uncommitted and untracked work. An unknown `REF`
  exits 1 with an error; it never reports "nothing changed".
- **a project root below the git top level**: paths are relative to `--root`.

Symbol mode seeds on the **definition**, not on every mention. Tracing from
every file that says the word makes the walk start everywhere and mean
nothing. The symbol is regex-escaped, so `$store` and `a.b` mean what they
say. A definition is a declaration keyword before the name (`function`,
`class`, `def`, `fn`, `fun`, `val`, `type`, ...), a modifier-led member
(`public static Foo name(`), a Go method (`func (r *T) Name(`), an assignment
(`name = function`, a top-level `NAME = ...`) or `#define`. A name after
`extends` or `implements` is a use, not a definition. If no definition matches,
every file that mentions the symbol is a seed and the report says so;
`<symbol> --file <path>` skips the guess and takes that file as the definition.

Searching uses `git grep` inside a work tree, so `.gitignore` is honoured and
no `rg` is needed; outside git it is `grep -r` with `.git`, `node_modules`,
`dist`, `build` and the graph's own directory excluded.

## Reading the report

The first line is always
`blast-radius: seeds=<n> affected=<n> depth=<d> edges=<e> gaps=<k>`: seeds and
affected files, the deepest level reached, edges in the whole import graph
(`0` means the graph is empty, not that nothing depends on the seed) and the
number of blind spots. Then `## ` sections, each printed only when it has
content (Seeds always): `Seeds`, `Depth 1`, `Depth 2`..., `Name matches`,
`Tests to run`, `Blind spots`. Output is sorted, and `--max` keeps the first
rows by path at each depth, so two runs print the same bytes.

Rows are `path:line -> via`: that file imports `via` at that line. Depth 1
imports a seed directly; depth 2 imports something at depth 1. Breakage is
near-certain at depth 1 and increasingly speculative after that.

Four things need care:

**`[inferred import, verify]`** — the edge came from a path alias, a baseUrl
specifier or a unique-suffix match, not a literal relative path. Usually
right; open it before acting.

**The name-match section** — in symbol mode, files where the name appears but
no import connects them to the seed. Those are usually a *different symbol
with the same name*. Never fold them into the blast radius unread.

**Tests to run** — affected, name-matched and changed files that look like
tests: `*.test.*`, `*.spec.*`, `test_*.py`, `*_test.py`, `*_test.go`,
`*Tests.cs`, `*Test.java`, `*_spec.rb`, and anything under `tests/`, `test/`,
`__tests__/` or `spec/`. Run them.

**Blind spots** — only imports that could have hidden an importer. Packages,
the standard library and system headers (`external-package`, `stdlib`,
`external-or-stdlib`, `external-or-jdk`, `external-crate`, `system-header`)
are expected not to resolve and are not counted. What remains is counted in
the seeds' own directories, by reason, and any unresolved import anywhere
whose name matches a seed's file name is listed as a *possible missed
importer*: a Vue `@/lib/auth` that no alias resolved still points at
`src/lib/auth.ts`. If that list is not empty, grep is the fallback for that part.

Exit codes: `0` ok or nothing changed; `1` usage error, an unknown `--base`, or
the graph could not be built; `2` the symbol appears nowhere. Unknown flags and
a flag with no value are usage errors, not ignored.

## What it cannot see

It follows imports. Anything wired at runtime is invisible:

- a route table or URL map
- a dependency-injection container
- a plugin or handler registry keyed by string
- reflection, `getattr`, `require` of a computed path
- templates, config, and migrations that name a symbol in text

So when the thing you are changing is *registered* rather than *imported* — a
handler, a serializer, a migration, a CLI subcommand — run a grep as well.
The report says this on every run, unconditionally, including when every
import resolved cleanly. That is deliberate: a clean run is exactly when a
reader is most likely to mistake it for a complete answer.

"Nothing imports the seed" is three different statements — a genuine leaf, a
runtime-wired module, or a resolution gap. The report distinguishes them.

## How resolution works

An import string becomes a file path, or it is dropped. It is never guessed.

1. **Relative** (`./x`, `../x`) — join with the importing file's directory,
   normalize, then try the path, then each extension, then `/index.*`,
   `/__init__.py` or `/mod.rs`.
2. **Aliased** — every `tsconfig.json`/`jsconfig.json` in the repo, not just
   the root one, because in a monorepo each package declares its own
   `paths`. The longest matching scope wins. Same for composer PSR-4.
3. **Module-rooted** — every `go.mod` in the repo, scoped the same way. The
   module prefix must end at a path boundary, or a sibling module named
   `example.com/app-contrib` resolves into `example.com/app`'s tree.
4. **Dotted** (`a.b.C`) — tried as a path, then as a unique path *suffix*.
5. **Nothing unique** — dropped, with a reason, to `unresolved.tsv`.

Ambiguity is always a drop. If two files in different directories share a
name and the import is not path-qualified, picking one is how a graph starts
lying, and a wrong edge in a blast-radius report is worse than a missing one:
a missing edge makes you look further, a wrong one makes you stop looking.

TypeScript ESM is special-cased: `./x.js` also tries `./x.ts`, because that
is what NodeNext codebases actually write.

## Languages

JavaScript and TypeScript (incl. JSX, Vue, Svelte, Astro), Python, Go,
Java/Kotlin/Scala/Groovy, C#, Rust, Ruby, PHP, C/C++/Objective-C, shell.

Eight families have a fixture under `tests/fixtures/imports/<family>/`
carrying an `EXPECTED.tsv` of the edges the extractor must find — 226 in
all. `scripts/check.sh` asserts the exact set, so a missing edge and an
invented one both fail.

The fixture and the expected-edge list were written independently and then
reconciled against the source, one disagreement at a time. That is what the
traps are for, and they earned their keep: an `import` inside a Java text
block, a Kotlin raw string, a C++ `R"( )"` literal, a Ruby heredoc, a PHP
nowdoc, a Ruby `=begin` block and a JS template literal all produced real
edges before the fixtures caught them, as did `#include <memory>`
suffix-matching `src/util/memory.hpp`, `import logging` matching a repo's
own `logging.py`, and a `use Roundable;` trait composition read as a
namespace import. A Go `import ()` left grouped-import state open so every
later string in the file became a dependency. A UTF-8 BOM and CRLF line
endings each defeated every anchored pattern in a file. Thirteen defects in
total, every one now pinned.

The remaining deliberate difference is Python: when a statement is
`from . import a, b`, this emits an edge to the package `__init__.py` as
well as to each submodule, because importing a package really does execute
its `__init__`. The fixture author would emit only the submodules. Both are
defensible; the extra edge is true, and for a blast radius an edge that is
true and unhelpful costs far less than one that is missing.

Adding a language means a branch in `scan()` and a branch in `resolve()` in
`scripts/code-graph.awk`, plus a fixture. No grammar, no dependency.

## Cost

The graph rebuilds on every run by default, because a cached graph quietly
describing yesterday's imports is worse than no graph. `--cached` skips it for
a tight loop. The build is one awk pass over the source files; if it ever
becomes the slow part on your repo, that is worth knowing and `--cached` is
the escape hatch. A `--diff` that includes a deleted or renamed-away file
ignores `--cached` and says so: the cached graph cannot hold edges to a file
that was not there when it was built. The graph is written to a temp file and
renamed into place, and a failing extractor leaves the previous graph untouched.
