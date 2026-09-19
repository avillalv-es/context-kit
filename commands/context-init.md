---
description: Set up or reorganize this repo's three-tier context layout
---

Use the `context-cleanup` skill.

Determine the mode yourself:

- If the argument below is `bootstrap`, or the session-start hook asked for the
  layout to be created, run **Mode 0: Bootstrap**.
- If no `CLAUDE.md` exists at the project root, run **Mode A: Initialize**.
- If `CLAUDE.md` exists but does not contain a `## Context layout` section,
  run **Mode A**, adopting the existing file rather than replacing it.
- If `CLAUDE.md` already contains a `## Context layout` section, run
  **Mode B: Cleanup**.

State which mode you selected and why, in one line, before you begin.

Additional instruction for this run, if any: $ARGUMENTS
