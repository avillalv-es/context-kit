## PR train

When an agreed plan holds two or more asks that would each be their own PR
(different areas, independently revertable: a UI change plus a roles change),
run it as a PR train with the `pr-train` skill. Decide for every new ask; one
ask, or tightly coupled changes, stay one PR.

- One branch and PR per task; `.claude/handoff/<train>.md` tracks the plan.
- Tasks with disjoint files run in parallel worktrees; shared files (docs,
  version, changelog) are applied afterwards, in order, so nothing conflicts.
- After each PR or parallel batch, update the handoff and ask me to `/compact`.
- If `.claude/handoff/` holds a train with `status: active`, read it before
  anything else and continue from its next unchecked task.
- Turn this off with `/pr-train off`.
