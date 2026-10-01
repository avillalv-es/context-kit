# Mode R — Refresh

Read this only when Mode R is the mode. The layout is already in place:
bring the plugin-owned sections of `CLAUDE.md` up to date, and give a
bootstrap-only file the survey it never had. Change nothing else. Do not
commit.

---

### R1 — Scaffold

Run A2 from `references/mode-a-initialize.md`: create whichever of the layout
folders and files is missing, and overwrite nothing.

### R2 — Stamp

```
sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" stamp CLAUDE.md
```

It adds the sections that are missing, rewrites the outdated ones between
their markers, wraps blocks written by 0.4.x in markers, and leaves a section
that was turned off alone. Edits inside the markers are overwritten, which is
the point: the text comes from the plugin. Everything outside the markers is
left exactly as it was. Keep its output for R4, and pass on any warning it
prints about a block it left untouched.

### R3 — Survey a bootstrap-only file

Look at `CLAUDE.md` outside the managed blocks, meaning outside the
`context-kit` markers, the unmarked 0.4.x `## Context layout` and
`## Lean execution` blocks, and the off lines. If nothing there is a `## `
heading, the file was bootstrapped and never surveyed. Run Mode A's A1 survey,
then write A3's sections (the "if no `CLAUDE.md` exists" list), and insert them
after the title and before the first managed block. If the file has `## `
headings of its own, skip this step.

### R4 — Report

One line: what R1 created, the R2 output, and whether R3 ran. If the line
count passes 200, add that `/context-init cleanup` will rebalance it.
