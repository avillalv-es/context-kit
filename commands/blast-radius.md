---
description: What breaks if this changes - trace importers of a symbol, a file, or the current diff
---

Use the `blast-radius` skill, and follow its procedure: open every depth-1
importer and give it a verdict. Do not stop at the list.

Pick the mode from the argument:

- no argument: `--diff`, everything changed in the working tree
- an existing path, or anything with a `/` or a file extension (`src/lib/auth.ts`): `--file <path>`
- anything else (`verifySignature`): a symbol
- `--diff --base main`: everything changed since branching from `main`
- `<symbol> --file <path>`: the symbol as defined in that one file
- `--depth N`, `--max N`, `--cached`: passed straight through

Change nothing unless asked. Say plainly which rows are resolved imports and
which are name matches.

Argument, or the mode: $ARGUMENTS
