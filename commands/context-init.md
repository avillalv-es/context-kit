---
description: Set up, refresh or reorganize this repo's three-tier context layout
---

Use the `context-cleanup` skill.

Determine the mode yourself. The first line that fits wins:

- The argument below is `bootstrap`, or the session-start hook asked for the
  layout to be created: **Mode 0: Bootstrap**.
- The argument is `cleanup`: **Mode B: Cleanup**, the audit. If there is no
  `CLAUDE.md` yet, run **Mode A** instead.
- The argument is `off <section>` or `on <section>`: run
  `sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" off <section> CLAUDE.md`
  (or `on`), report its output in one line, and stop. No other mode runs.
- No `CLAUDE.md` exists at the project root: **Mode A: Initialize**.
- `CLAUDE.md` exists but has neither a `## Context layout` heading nor a
  `context-layout` marker (`<!-- context-kit:begin context-layout -->`, or
  its `off` form): **Mode A**, adopting the existing file rather than
  replacing it.
- Otherwise the layout is present: **Mode R: Refresh**, which stamps the
  plugin-owned sections up to date and leaves the rest of `CLAUDE.md` alone.

State which mode you selected and why, in one line, before you begin.

Additional instruction for this run, if any: $ARGUMENTS
