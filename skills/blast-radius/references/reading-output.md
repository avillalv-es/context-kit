# Reading blast-radius output

Read this when the stats line shows `gaps` above 0, when a section is not
self-explanatory, or when the answer is "nothing imports it".

## The stats line

`blast-radius: seeds=<n> affected=<n> depth=<d> edges=<e> gaps=<k>`

- `seeds`: files the walk started from. Symbol mode: the file(s) defining the
  symbol. `--file`: that file. `--diff`: every changed file, including deleted
  files and the old path of a rename (tagged `[deleted]` or `[renamed to ...]`;
  their importers are the ones that break).
- `affected`: files that reach a seed through imports, at any depth.
- `depth`: the deepest level that has any. The walk stops at `--depth`.
- `edges`: import edges in the whole graph. `0` means the graph is empty
  (no source files, or nothing resolved), which says nothing about the seed.
- `gaps`: unresolved imports that could hide an importer (see Blind spots).

## Sections

- `Seeds`: one path per line, with a note if no definition was found (every
  file mentioning the symbol is then a seed; scope it with `--file`).
  `[no resolved imports touch this file]` means no edge in the graph involves it.
- `Depth N`: `path:line -> via`. Depth 1 imports a seed directly; depth 2 imports
  something at depth 1. Breakage is near-certain at depth 1 and speculative after.
- `Name matches`: symbol mode only. The name appears, no import path connects it.
- `Tests to run`: affected, name-matched and changed files that look like tests
  (`*.test.*`, `*.spec.*`, `test_*.py`, `*_test.go`, `*Tests.cs`, anything under
  `tests/`, `__tests__/`, `spec/`). Run these, then the repo's wider suite if the
  change is large.
- `Blind spots`: only imports that could have hidden an importer. Packages, the
  standard library and system headers are not counted. It has two parts: how many
  unresolved imports sit in the seeds' own directories (by reason), and
  "possible missed importers", where an unresolved import's name matches a seed's
  file name. Open each of those.

## Common unresolved reasons

- `relative-path-has-no-file`: a `./x` that points at nothing. Often a typo, a
  generated file, or a file extension the extractor does not know.
- `ambiguous-name`: two files fit and the extractor refused to pick one.
- `external-package` on an `@/...` or `~/...` specifier: an alias the extractor
  could not read, so a real importer is missing. It is listed as a possible
  missed importer when its name matches a seed.

## When nothing imports the seed

Decide which of these it is, and say so:

1. A leaf: an entry point, a script, a test. Check it is named in a build or run config.
2. Wired at runtime: DI container, route table, plugin registry, string-keyed
   factory, reflection. `git grep -n -w <name>` for the registration.
3. A resolution gap: its importers use a form that did not resolve. Look at
   `Blind spots`, then grep for the file name.
