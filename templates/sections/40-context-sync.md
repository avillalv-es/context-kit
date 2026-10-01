## Context sync

Project markdown (PROGRESS.md, docs/, notes) is the source. `knowledge/`, `findings/`,
`.claude/rules/` and `.claude/skills/` are where it gets routed.

- Before the first request of every session, use the `context-sync` skill. Its first
  step is one command; if it prints nothing, carry on.
- If something changed, a background subagent routes it while the request goes ahead.
  Report the result in one line.
- Mid-session, a settled conclusion or dead end goes to `finding-ledger` and a repeatable
  procedure to `skill-capture`, never into this file. Turn this off with `/context-sync off`.
