---
description: Route PROGRESS.md, docs and notes into knowledge/, findings/, rules and skills, or turn the session-start sync on or off
---

Use the `context-sync` skill.

With no argument, or `now`: run it here, in the foreground. Spawn the routing
subagent with `run_in_background: false`, wait for it, review its table, mark
what it processed, and report the one line.

With `off` or `on`: run
`sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" off context-sync CLAUDE.md`
(or `on`), report its output in one line, and stop. Turning it off removes the
CLAUDE.md line that runs the sync at the start of every session.

With `sources add <glob>` or `sources list`: run
`sh "${CLAUDE_PLUGIN_ROOT}/scripts/context-sync.sh" sources <the rest>`, report
its output, and stop. A source is a root `*.md` file or anything under `docs/`
by default; `sources add 'notes/*.md'` adds more.

Argument, if any: $ARGUMENTS
