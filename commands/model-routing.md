---
description: Turn the CLAUDE.md model routing section on or off, or show its state
---

The Model routing section of `CLAUDE.md` is stamped from the plugin by
`claude-sections.sh`. Only that script touches it; never edit the block by hand.

- `off`: run
  `sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" off model-routing CLAUDE.md`
- `on`: run
  `sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" on model-routing CLAUDE.md`
- no argument, or `status`: run
  `sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" status CLAUDE.md`
  and report its `model-routing` line.

Report the result in one line and stop. If there is no `CLAUDE.md`, say so and
point to `/context-init`.

Argument, if any: $ARGUMENTS
