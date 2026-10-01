## Context layout

This project uses a three-tier layout. Do not add knowledge to this file on
your own initiative. If something seems worth keeping, say so in one line and
let me decide.

- Conditional knowledge lives in `.claude/rules/` with `paths` frontmatter.
- Reference and procedures live in `knowledge/` and `.claude/skills/`.
- A procedure that repeats gets captured into `.claude/skills/`. Tell me in one
  line after you create it; do not add it here.
- This file is capped at 200 lines.

To reorganize any of it, run `/context-init cleanup`.
