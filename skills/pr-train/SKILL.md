---
name: pr-train
description: Use when an agreed plan holds two or more asks that would each be reviewed as their own PR, when CLAUDE.md has a PR train section, when `.claude/handoff/` holds a train with status active, when the user asks to split work into PRs, run a PR train or resume one, or runs /pr-train. Do not use for a single ask, or for tightly coupled changes that belong in one PR.
---

# PR train

Several independently reviewable asks become several small PRs, built in order
or in parallel, with a temporary train file that carries the state across
`/compact`. Claude cannot compact itself and plugin hooks may be blocked, so
two things drive it: the train file, and the CLAUDE.md "PR train" section,
which reloads after compaction and says to read the file.

One ask, or changes a reviewer would want together, stay one PR. If the user
says stop or changes the plan, update the train file first.

## 1. Decide and split

- One task per independently reviewable ask, in dependency order.
- For each task, list the files it will touch.
- Files that more than one task would touch (README, changelog, version
  manifests, lockfiles, central registries or indexes) are **integration-owned**:
  no task edits them while it builds.

## 2. Pick the strategy

- **Stacked**: a later task needs an earlier one, or tasks share files. Each
  branch is based on the previous branch, and each PR's base is that branch.
- **Independent**: each branch comes off fresh main.

## 3. Write the train file

```sh
mkdir -p .claude/handoff
printf '*\n' > .claude/handoff/.gitignore
cp "${CLAUDE_PLUGIN_ROOT}/templates/handoff.md" .claude/handoff/<slug>.md
```

The `.gitignore` containing `*` keeps the directory temporary: it is never
committed. Fill in the file, reading the repo conventions from CLAUDE.md (issue
per PR and `Closes #n`, ship script, docs-must-update rule, test command,
commit style), then delete the template comments. Open each task's issue now if
the repo wants one, and record the number.

## 4. Lanes

**Parallel lane**: two or more tasks with disjoint owned files and no
dependency between them. Spawn one subagent per task in a single message:
`isolation: "worktree"`, `model: "sonnet"` (per Model routing), the task, its
base, an explicit owned-files list, and "do not touch integration-owned files,
do not push, do not open a PR". Each returns its branch, commits, test result
and integration notes: the exact shared-file edits it needs. Read
`references/parallel-lane.md` for the prompt and the return format. A task that
needs another's result goes in a later batch.

**Sequential lane**: branch from the task's base, delegate the coding to a
Sonnet subagent (`model: "sonnet"`), and keep review in this session.

## 5. Integrate, in task order

For each task:

1. Rebase its branch onto its base (the previous branch when stacked, fresh
   main when independent). It is clean because the file sets were disjoint; a
   conflict means a shared file was missed, so add it to the train file.
2. Apply that task's shared-file edits and commit them.
3. Run the repo's tests the repo's way.
4. Read the diff. This session decides; send fixes back to the builder.
5. Push the branch in its own command, never combined with anything that
   mentions the main branch, because some org guards pattern-match that.
6. Open the PR the repo's way: issue link, ship script, attribution. For a
   stacked train its base is the previous branch.

## 6. Handoff, then compact

Append a Done log entry (PR URL, what changed, notes for the next task), rewrite
In progress, tick the tasks, set `updated:`. Then stop and ask the user to run
`/compact`. Claude cannot do it. Never leave state only in the conversation.
After the last task skip this and go to step 8.

## 7. Resume

On a new session or after compaction, an active train file means: read it and
the plan, check the state with `git status`, `git log` and `gh pr list`, finish
whatever In progress records, then continue from the next unchecked task. If
the train file and git disagree, git wins; fix the file first. With two active
trains, ask which one.

## 8. Finish

Set `status: complete`. Post a table of the PRs: number, title, base, status.
Leave the file; it is gitignored, and a complete train is never resumed. For a
stacked train, say the PRs merge in order and each next PR is retargeted to the
main branch after the one below it merges.
