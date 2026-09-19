---
name: shortcut-ledger
description: Use when the user asks what shortcuts or simplifications were deferred, asks to list the technical debt markers, asks what was marked to do later, asks for the shortcut ledger, or runs /shortcut-ledger. Harvests every shortcut comment in the repo into one tracked list so a deferral cannot quietly become permanent. Reads and reports only, changes nothing.
---

# Shortcut ledger

Every deliberate simplification that cut a real corner is marked with a
`shortcut:` comment naming its ceiling and upgrade path. This collects them
into one list.

Adapted from ponytail-debt (MIT, Dietrich Gebert). See `NOTICE`.

## Scan

One grep. Do not read files one by one.

```bash
grep -rnE '(#|//|--|;) ?shortcut:' . --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=.venv --exclude-dir=__pycache__
```

Each hit is one row. Requiring the comment prefix keeps prose that merely
mentions the convention out of the ledger. Add other comment prefixes if the
stack uses them.

## Output

One row per marker, grouped by file:

```
<file>:<line>, <what was simplified>. ceiling: <the limit named>. upgrade: <the trigger to revisit>.
```

The convention is `shortcut: <ceiling>, <upgrade path>`, so pull both straight
from the comment.

**Flag the rot risk.** Any `shortcut:` comment that names no upgrade path or
trigger gets a `no-trigger` tag. Those are the ones that silently become
permanent — a ceiling with no trigger is a decision nobody will revisit.

End with:

```
<N> markers, <M> with no trigger.
```

Nothing found: `No shortcut: markers. Clean ledger.`

## Options

- Owner per row: add `git blame -L<line>,<line> -- <file>` for each hit. Only
  when asked — it is one subprocess per marker.
- Persist it: if the user asks, write the ledger to `findings/shortcuts.md`.
  Do not write it unprompted.

## Boundaries

Reads and reports. Changes nothing, fixes nothing, commits nothing. One-shot.
