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
2. The Lean execution section in `CLAUDE.md` is a copy of the ruleset at the
   level it was stamped, so it needs re-stamping to follow a change. If the
   argument is `lite`, `full` or `ultra`, run
   `sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" status CLAUDE.md`.
   When its `lean-execution` line says `ok`, `outdated` or `legacy`, run
   `sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" stamp CLAUDE.md --level <the new level>`,
   which rewrites that block in place and brings the other managed sections up
   to date too. Any other answer (`missing`, `off`, `legacy-unbounded`, or no
   `CLAUDE.md`) means the project does not carry the block, so leave the file
   alone. For `off`, do not re-stamp: the block keeps whatever it says until
   `/context-init off lean-execution` removes it.
3. Confirm the new level in one line, and whether the block was re-stamped,
   and stop.

If there is no argument, read the level file (treat a missing file as
`full`) and report the current level in one line, then briefly explain what
each level changes.

Argument, if any: $ARGUMENTS
