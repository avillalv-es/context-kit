---
description: Set up a Forge app - write knowledge/forge/ and the CLAUDE.md Forge section, refresh them, or turn the section off or on
---

With no argument: use the `forge-init` skill. It asks which Forge features the
app uses, installs or refreshes the matching `knowledge/forge/` files, writes
`knowledge/forge/app.md` (features, apps, secrets, env), adds the Forge section
to `CLAUDE.md`, then plans every code change in plan mode. Entra sign-in is
always included.

With `status`: run
`sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" status CLAUDE.md`,
report its `forge` line (no line means the section was never added), and say
whether `knowledge/forge/README.md` exists. Change nothing.

With `off`: run
`sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" off forge CLAUDE.md`
and report its first line. `knowledge/forge/` is left as it is.

With `on`: run
`sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" on forge CLAUDE.md`
and report its first line.

If there is no `CLAUDE.md`, say so and point to `/context-init`.

Argument, if any: $ARGUMENTS
