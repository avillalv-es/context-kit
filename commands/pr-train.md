---
description: Split a multi-ask plan into a PR train, resume or inspect one, or turn the CLAUDE.md section off or on
---

Use the `pr-train` skill.

With no argument: if `.claude/handoff/` holds a train with `status: active`,
resume it (skill step 7). Otherwise split the plan agreed in this session into
a train (steps 1 to 4), or say in one line that it holds one ask and needs no
train.

With `status`: read the active train file and show its task list (id, title,
branch, PR, ticked or not) plus its In progress note. Change nothing.

With `off`: run
`sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" off pr-train CLAUDE.md`
and report its first line.

With `on`: run
`sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" on pr-train CLAUDE.md`
and report its first line.

Argument, if any: $ARGUMENTS
