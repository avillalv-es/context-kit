# Parallel lane

Read this when about to spawn a batch. Tasks may build at the same time only
when their owned files are disjoint and none needs another's output. All of a
batch's branches start from the same commit; integration (step 5) then rebases
them into the train's order, which is clean precisely because no file is shared.

## Spawn

One message, one Agent call per task, all in that message so they run together.
Each call: `isolation: "worktree"`, `model: "sonnet"`, and this prompt, filled in:

```
You are building one task of a PR train, in your own git worktree.

Task <id>: <title>
Acceptance: <criteria from the train file>
Setup: create branch <branch> from <base commit or branch>.

Own these files, and only these: <owned files and globs>.
Integration-owned (README, changelog, version manifests, lockfiles, registries,
indexes): do NOT edit them. If the task needs a change there, write it down as
an integration note instead.
New tests go in a new file of their own, never in a shared registry or runner.

Repo conventions: <test command, docs rule, commit style and attribution line>.
Run the tests until they pass. Commit with conventional commits.
Do not push. Do not open a PR. Do not touch other branches.

Return, in under 30 lines: the branch name; `git log --oneline <base>..HEAD`;
the diffstat; the test result; anything you changed outside your file list and
why; and an INTEGRATION NOTES block with the exact shared-file edits needed
(file, where, the text to add).
```

Add anything the builder cannot read from the repo: the plan section for its
task, constraints from other tasks, names it must agree on with a sibling.

## Collect

- Record each returned branch, and its integration notes, in the train file's
  In progress section before integrating; a compaction mid-batch must lose
  nothing.
- A builder that touched a file it did not own: move that file to the shared
  list and redo that edit at integration, rather than letting two branches
  carry it.
- The builder's report is a claim. Integration still runs the tests and reads
  the diff.
