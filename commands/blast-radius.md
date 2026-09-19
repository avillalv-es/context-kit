---
description: What breaks if this changes - trace importers of a symbol, a file, or the current diff
---

Use the `blast-radius` skill.

Recognised arguments:

- a bare symbol name — trace what depends on that function, class or constant
- `--file <path>` — trace what depends on that file
- `--diff` — trace everything changed in the working tree (the audit case)
- `--diff --base main` — trace everything changed against a branch
- `--depth N`, `--max N`, `--cached` — passed straight through

Report the affected set. Change nothing unless asked, and say plainly which
rows are resolved imports and which are name matches.

Target, or the mode: $ARGUMENTS
