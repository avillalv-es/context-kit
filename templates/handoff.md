---
status: active
plan: <path to the agreed plan>
base: <branch the train starts from, e.g. main>
strategy: stacked
updated: <YYYY-MM-DD>
---

<!--
  PR train file. Copy to .claude/handoff/<slug>.md, fill it in, then delete
  these comments: a resumed session reads the whole file, so keep it short.
  The directory has its own .gitignore containing `*`; never commit this file.

  status    active until every task is ticked, then complete. Only an active
            train is resumed; a complete one never is.
  plan      path to the agreed plan, so a fresh session can re-read it.
  base      the branch the first task starts from (usually main).
  strategy  stacked: each branch is based on the previous one, and each PR's
            base is the previous branch. Use it when a task needs an earlier
            one or tasks share files.
            independent: each branch comes off fresh main.
  updated   touch it on every edit. If git disagrees with this file, git wins.
-->

# Train: <slug>

## Goal

<!-- One to three lines: what the whole train delivers and why it is split. -->

## Repo conventions

<!-- Copied from CLAUDE.md so a session after /compact need not re-derive them. -->
- Issue per PR, linked with `Closes #<n>`: <how an issue is opened here>
- Ship script: <command, or none>
- Docs: <rule for updating folder docs with code, or none>
- Tests: <the repo's test command>
- Commits: <style, and the attribution line to end them with>

## Tasks

<!--
  One block per task, in dependency order. Tick the box when its PR is open.
  owns   every file the task may touch. Two parallel tasks must not overlap.
  base   main, or the previous task's branch when stacked.
-->
- [ ] T1 <title>
  - branch: <type/short-name>   base: <main | previous branch>
  - owns: <files or globs>
  - accept: <what must be true for the PR to be done>
  - issue: #<n>   pr: <URL, once open>
- [ ] T2 <title>
  - branch:    base:
  - owns:
  - accept:
  - issue:   pr:

## Shared files (integration-owned)

<!--
  Files that more than one task would touch (README, changelog, version
  manifests, lockfiles, central registries or indexes). No task edits them
  while it builds; integration applies each task's edit afterwards, in order.
-->
- <path>: <what each task adds>

## Done log

<!-- One entry per finished task, appended when its PR is open. -->
### T1 <title> - <PR URL>
- Changed: <one or two lines>
- For the next task: <anything it must know or build on; the branch to start from>

## In progress

<!--
  Mid-task state, rewritten before every long step, so an automatic compaction
  in the middle of a task loses nothing. Clear it when the task is done.
-->
- task: <id, or none>
- branch / worktrees: <names and paths>
- last done: <step>   next: <step>

## Open questions

<!-- Things the user still has to decide. Remove each once answered. -->
- <none>
