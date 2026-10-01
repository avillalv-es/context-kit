---
name: context-sync
description: Use when CLAUDE.md says to run the context sync before the first request of a session; when the user asks to sync, refresh or update knowledge, findings, rules or skills from PROGRESS.md, docs or notes; when those files changed; or runs /context-sync. Do not use mid-task, or to write to CLAUDE.md.
---

# Context sync

Project markdown (PROGRESS.md, docs/, notes) is the source; `knowledge/`, `findings/`,
`.claude/rules/` and `.claude/skills/` are where it is routed.

## 1. Check, once per session

```
sh "${CLAUDE_PLUGIN_ROOT}/scripts/context-sync.sh" check
```

**No output means stop**, with no message to the user. Otherwise each line is one thing to do.
A context-kit session note may already say "unchanged" (stop) or list the lines (go to step 2).

## 2. Act, by line

- `layout missing`: suggest `/context-init` in one line, and stop.
- `sections ...`: tell the user in one line to run `/context-init`. Never edit CLAUDE.md
  here; it is governance-protected.
- `findings lessons-stale`: run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/findings.sh" reflect --if-stale`.
- Every other line (`source`, `findings changed`, `index`, `rule`, `skill`): spawn ONE
  subagent (Agent tool, `model: "sonnet"` or the nearest model org policy allows,
  `run_in_background: true`). Give it those lines, the plugin root
  (`${CLAUDE_PLUGIN_ROOT}`, as a path), and the instruction to read
  `${CLAUDE_PLUGIN_ROOT}/skills/context-sync/references/routing.md` and follow it.
  Then carry on with the user's request; do not wait.

## 3. When the subagent returns

Review its table. This is the judgment step: the lower tier wins a tie, status chatter
stays in its source, and nothing was written to CLAUDE.md. Move an obvious misroute. Then:

```
sh "${CLAUDE_PLUGIN_ROOT}/scripts/context-sync.sh" mark <the paths it processed>
```

Skip any path you edited yourself since step 1. Report ONE line, for example
`context sync: PROGRESS.md -> 2 knowledge, 1 finding; INDEX +3 rows`. If the subagent
failed, mark nothing and say so in one line; the next session retries.

Not for one settled conclusion (`finding-ledger`), a repeatable procedure (`skill-capture`),
or rebalancing CLAUDE.md (`/context-init cleanup`).
