---
description: Set or show the lean execution level (lite/full/ultra/off)
---

Use the `lean-execution` skill.

The level lives in one file: `${CLAUDE_PLUGIN_DATA:-~/.claude/context-kit}/level`
(one line: `lite`, `full`, `ultra`, or `off`). `UserPromptSubmit`'s `do_mode`
hook also writes this file when it can run — writing it here too is safe and
idempotent, both ever write the same value for the same argument.

If the argument is `lite`, `full`, `ultra`, or `off`:

1. Write it to that file (create the file, and the directory if missing).
2. If this project's `CLAUDE.md` has a `## Lean execution` heading (stamped
   by the context-cleanup skill's Mode 0/A step A4b), re-run that same step
   now so the stamped block reflects the new level. Otherwise it stays
   frozen at whatever level was active the first time it was stamped.
3. Confirm the new level in one line and stop.

If there is no argument, read the level file (treat a missing file as
`full`) and report the current level in one line, then briefly explain what
each level changes.

Argument, if any: $ARGUMENTS
