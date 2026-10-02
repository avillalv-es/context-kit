# context-kit

A three-tier context layout **and** a lean execution ruleset for Claude Code,
packaged as one plugin. Works in any repo that involves code: a service, a
library, a dbt project, a pile of notebooks.

Two premises.

**Every line in `CLAUDE.md` is a tax on every session and every subagent,
forever.** Knowledge that only matters when you touch the database should not
be loaded when you are editing a stylesheet.

**Most tokens are not spent on knowledge at all.** They go on reading more than
was needed, writing more than was needed, and explaining more than was needed.
Organizing `CLAUDE.md` does nothing about any of those.

It is deliberately **not** a retrieval tool. It does not index your code and it
embeds nothing. Code structure is already in the code, and a good agent can
read it. What an agent cannot read is *why* a column is nullable on purpose, or
which of two contradictory requirements is the live one.

There is one graph here. `/context-graph` draws the *context layout* — the
tiers, the rules, the globs they claim, the skills, and who touched what —
because that is the part nothing else can see. A rule whose `paths:` match no
file is invisible in every view except this one.

It also draws a **file-level** map of the code, and `/blast-radius` walks that
map backwards to answer *what breaks if I change this*. That is the one
question grep structurally cannot answer. It stops well short of a symbol
index: it knows which file depends on which file, not which function calls
which, and that is the trade — a fraction of the machinery, and it stays true
for far longer.

---

## What it does

| | |
|---|---|
| **Bootstraps itself** | First session in a repo with no context layout, Claude creates or appends the managed `CLAUDE.md` sections — as a visible diff you can decline. Offered once, then never again. |
| **Injects a lean ruleset** | ~30 lines into every session *and every subagent*: reuse before writing, locate before reading, answer before explaining. |
| **Captures skills on its own** | Finish a procedure worth repeating and Claude writes `.claude/skills/<name>/SKILL.md` and tells you in one line. No permission prompt, no ceremony. |
| **Detects repeats** | A silent ledger counts shell commands. Three runs of the same procedure with no skill covering it, and the next session says so. |
| **Keeps its sections current** | Re-running `/context-init` re-stamps the sections the plugin owns in `CLAUDE.md`, adding missing ones and rewriting outdated ones in place. |
| **Audits the layout** | `/context-init cleanup` classifies every line of `CLAUDE.md` and shows you a table before moving anything. |
| **Draws the layout** | `/context-graph` renders tiers, rules, skills and recorded agent activity as a graph you open in a browser, and names the rules that can never fire. |
| **Remembers what was settled** | `/finding` logs a conclusion, a dead end or a correction; `reflect` aggregates them into `LESSONS.md` so a long investigation survives compaction. |
| **Traces impact** | `/blast-radius --diff` walks the import graph backwards from everything you changed and lists what is downstream, ranked by distance, with a line to open in each file. |

No Node, no Python, no install script. The hooks are POSIX `sh` (with a
PowerShell twin), which is what Claude Code already runs.

---

## The three tiers

| Tier | Lives in | Loads | Holds |
|---|---|---|---|
| 1 | `CLAUDE.md` | every session, always | routing and the handful of facts that are wrong-answer-generating everywhere |
| 2 | `.claude/rules/*.md` with `paths:` frontmatter | only when a matching file is touched | conventions and pitfalls scoped to one area |
| 3 | `knowledge/*.md`, `.claude/skills/*/SKILL.md` | only when looked up or invoked | reference material and repeatable procedures |

Plus one bucket that is not a tier: **delete**. Directory trees, dependency
lists, file inventories and architecture summaries are all derivable by
looking. They do not go anywhere.

Hooks are not a tier either — they are the escape hatch, for rules where being
ignored once is an incident. The reasoning, including the trap that makes
`SessionStart` injection look free when it is not, is in
[docs/three-tier-model.md](docs/three-tier-model.md).

## The classification test

For each line or coherent block of knowledge, ask:

> If I never saw this, would I get something wrong on a task that has nothing
> to do with this knowledge's subject?

- **Yes** → tier 1. Rare.
- **No, but it applies whenever certain files are touched** → tier 2.
- **No, it is reference or narrative** → tier 3.
- **No, it is a procedure that repeats** → tier 3, as a skill.
- **It is derivable by reading the codebase** → delete.

Break ties toward the lower tier. A tier-2 rule that should have been tier 1
produces one visible mistake you can correct. A tier-1 entry that should have
been tier 2 produces invisible drag on every session forever.

---

## Install

```
/plugin marketplace add avillalv-es/context-kit
/plugin install context-kit@context-kit
```

Restart the session. The first session in any repo without a context layout
will offer to create one.

Or copy the pieces in by hand, for a single project:

```bash
cp -r skills/* <repo>/.claude/skills/
cp commands/*.md <repo>/.claude/commands/
```

The hand-copy path gets the skills and commands but **not** the hooks, so you
lose the bootstrap, the always-on ruleset, and repeat detection. Use the plugin
install unless you have a reason not to.

> **Filename note.** Skill files must be `SKILL.md` — lowercase `.md`.
> `SKILL.MD` resolves on Windows and macOS but is silently invisible on a
> case-sensitive filesystem, which is where most containers and CI runners
> live. Same for commands: the filename becomes the command name, so
> `context-init.md` gives you `/context-init`.

### Windows without Git Bash

The hooks are registered to run under `sh`, which covers macOS, Linux and
Windows with Git Bash installed. If Claude Code on your machine falls back to
PowerShell, point `hooks/hooks.json` at the twin instead — replace each

```json
"command": "sh",
"args": ["${CLAUDE_PLUGIN_ROOT}/hooks/context-kit.sh", "<action>"]
```

with

```json
"command": "powershell.exe",
"args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "${CLAUDE_PLUGIN_ROOT}/hooks/context-kit.ps1", "<action>"]
```

Both scripts are tested and behave identically. Only one is registered by
default so that the other does not fail on every session of the wrong platform.

### Hooks silently not firing

Symptoms: no ruleset shows up in any session or subagent, no load error
anywhere, `~/.claude/context-kit/` never gets created — and it persists
across a full restart of the app, not just a new chat.

Run `/hooks`. If it reports something like *"Hooks Restricted by Policy —
Only hooks from managed settings can run. User-defined hooks from
`~/.claude/settings.json`, `.claude/settings.json`, and
`.claude/settings.local.json` are blocked,"* this is not a bug in this
plugin: your organization has a managed Claude Code settings tier configured
that restricts hook execution to what it centrally allowlists, and a
plugin-installed hook (registered through user-scope settings, whichever
project you installed it into) falls under exactly what that message names
as blocked. No change here can override it — that tier is deliberately
outside what user- or project-level configuration can touch. The only way
to actually get these hooks running is to have whoever administers your
org's managed settings allowlist them.

Skills and commands (`/context-init`, `/lean`, etc.) are a different
mechanism from hooks and are unaffected by this — they still run normally.
Nothing in the plugin gets removed or disabled to work around a blocked
hook; every fallback below is additive, and the hook it stands in for keeps
working exactly as designed the moment it's allowed to run.

| What the hook did | Fallback | How complete |
|---|---|---|
| `SessionStart`: offer to bootstrap a new project | Run `/context-init bootstrap` yourself | Full — already a documented manual path, hook or not |
| `SessionStart` + `SubagentStart`: inject the ruleset | `context-cleanup` Mode 0/A/R stamps it into `CLAUDE.md` under `## Lean execution` (`scripts/claude-sections.sh`, `references/mode-a-initialize.md` step A4b) | Full for your main session — `CLAUDE.md` loads every session regardless of hooks, and `do_session`/`Invoke-Session` skip re-injecting it once that heading exists, so this costs nothing extra where hooks work normally |
| `SubagentStart`: reach spawned subagents specifically | The same A4b stamp ends with an instruction telling the orchestrating session to paste that section into every subagent prompt it writes | Real, but compliance-based, not enforced — it works because Claude reads and follows it, not because anything guarantees it the way a hook does. Also: on a machine where `SubagentStart` *does* fire, a subagent gets the ruleset twice (hook + pasted prompt text) — there's no reliable way to detect hook-liveness and skip one, so this is accepted rather than solved |
| `UserPromptSubmit`: persist a `/lean <level>` change | `/lean` now reads and writes the level file itself (`commands/lean.md`) instead of assuming the hook already did it, and re-stamps `CLAUDE.md` to match | Full for the documented `/lean lite\|full\|ultra\|off` command. Not covered: typing a bare phrase like "stop lean" with no `/lean` prefix — that whole-message detection has no equivalent, but the formal command reaches the same end state |
| `PostToolUse`(Bash): count repeated commands, nudge `skill-capture` at 3+ | `skill-capture`'s SKILL.md now says to notice the same pattern in-context when no hook nudge is possible | Partial, by choice — session-scoped and best-effort, not a persistent cross-session count. The actual capture step is unaffected either way; only the automatic "you should look at this" prompt is weaker |
| `SubagentStart`(async) + `PostToolUse`(file/task/skill tools): activity ledger behind `/context-graph`'s OBSERVED layer | None | No equivalent, by choice. The only way to replicate it is a standing instruction to hand-log a ledger row after every relevant tool call, forever — real cost for a purely optional visualization that already degrades gracefully (`/context-graph` explicitly avoids reading an empty ledger as "never invoked" rather than showing wrong data) |

If you land here after a fresh debugging session of your own: the ruleset
not firing was chased as a plugin bug across four earlier PRs (manifest
`hooks` key on/off, version bumps) before anyone thought to check `/hooks`.
Those PRs' changes are still correct and worth keeping — they just weren't
the cause of this failure mode.

---

## Use

| Command | What it does |
|---|---|
| `/context-init` | Set up the layout, or refresh it if it is there. Picks its own mode. |
| `/context-init cleanup` | Audit and rebalance the layout. Stops at a table before moving anything. |
| `/context-init off\|on <section>` | Turn a managed `CLAUDE.md` section off, or back on. |
| `/context-sync [now\|off\|on\|sources add <glob>]` | Route PROGRESS.md, docs/ and notes into knowledge/, findings/, rules and skills. Runs on its own at session start through CLAUDE.md. |
| `/context-graph` | Draw the layout. `serve` for a URL, `vault` for Obsidian notes. |
| `/finding` | Record a finding; `/finding reflect` rolls them into `LESSONS.md`. |
| `/pr-train [status\|off\|on]` | Split a plan of several PR-sized asks into a PR train, resume an active one, or turn the `CLAUDE.md` section off or on. |
| `/blast-radius [<symbol> [--file P] \| <path> \| --diff [--base REF]]` | What breaks if this changes. No argument = `--diff`. Opens each importer and gives a verdict. |
| `/context-init bootstrap` | Scaffold and stamp the managed sections only. No survey. |
| `/skill-capture` | Turn a repeatable procedure into a project skill. |
| `/lean lite\|full\|ultra\|off` | Set the execution level. Persists across sessions. |
| `/lean-review [--repo]` | What can be deleted. Diff by default, whole tree with `--repo`. |
| `/model-routing [on\|off]` | Turn the Model routing section of `CLAUDE.md` on or off; no argument shows its state. |
| `/shortcut-ledger` | Every deliberate shortcut marked in this repo. |
| `/context-help` | The reference card. |

`/context-init` picks its own mode:

- **Mode 0 — Bootstrap.** Scaffold and stamp the managed sections. Cheap,
  idempotent, no judgment. This is what the hook triggers automatically.
- **Mode A — Initialize.** No `CLAUDE.md`, or one with no context layout.
  Surveys the repo and adopts existing content into the layout.
- **Mode R — Refresh.** The layout exists. Stamps the managed sections up to
  date, and surveys a `CLAUDE.md` that was only ever bootstrapped. This is
  what a plain `/context-init` does on a repo that already has the layout.
- **Mode B — Cleanup.** `/context-init cleanup`. Audits and rebalances the
  layout, including `.claude/skills/`.

Mode B **stops and shows you a table before moving anything**, and does not
proceed on implied approval. That is deliberate: this is the step where
knowledge gets silently lost if you let it run unattended.

Pass extra instructions straight through:

```
/context-init cleanup only audit, do not propose moves yet
```

Restart the session afterwards and run `/context` to see the real number.

### Managed sections

`/context-init` writes these sections into `CLAUDE.md`, each between
`<!-- context-kit:begin <id> -->` and `<!-- context-kit:end <id> -->` markers:

| Id | Section |
|---|---|
| `context-layout` | Context layout |
| `lean-execution` | Lean execution |
| `model-routing` | Model routing |
| `context-sync` | Context sync |
| `pr-train` | PR train |
| `blast-radius` | Blast radius |

Their text comes from the plugin (`templates/sections/`, and `hooks/rules.md`
for Lean execution), copied in by `scripts/claude-sections.sh` rather than
written by the model. Re-running `/context-init` refreshes them: missing
sections are added, outdated ones are rewritten in place, and a block from an
older version without markers is wrapped and upgraded. Anything you edit inside
the markers is overwritten, so change what you want outside them. Claude Code
strips the markers before it loads the file, so they cost no tokens.

To turn one off, run `/context-init off <section>` with one of the ids above.
The block becomes a single `<!-- context-kit:off <section> -->` line that a
refresh never adds back, and `/context-init on <section>` restores it.
`/context-init cleanup` treats managed blocks as the plugin's and does not
touch them.

### Model routing

The Model routing section tells the session to decide and to send the legwork
to subagents, passing `model` on every Agent call. Sonnet (always the latest)
explores, searches, researches, codes to an agreed plan, writes markdown and
runs tests. Opus plans, makes architecture and trade-off calls, gives review
verdicts and judges root causes; a session not running Opus sends those to an
Opus subagent. A model your organization restricts is never used. It is
stamped like the other managed sections; `/model-routing off` turns it off and
`/model-routing on` brings it back.

### Context sync

PROGRESS.md, `docs/` and notes change constantly, while `knowledge/` and
`findings/` do not. Context sync closes that gap. Project markdown is the
source, and `knowledge/`, `findings/`, `.claude/rules/` and `.claude/skills/`
are where it is routed.

The trigger is a `CLAUDE.md` section rather than a hook, so it works where org
policy blocks hooks. Before your first request in each session, Claude runs
the `context-sync` skill. Its first step is `scripts/context-sync.sh check`,
which prints one line per thing that changed and nothing at all when
everything is current.

When something has changed, one background Sonnet subagent routes it while
your request goes ahead:

- facts go to `knowledge/` with an INDEX row;
- decisions, dead ends and measured results go to `findings/`;
- path-bound conventions go to rules, with `paths:`;
- repeatable procedures go to skills;
- status chatter stays where it is, with one INDEX pointer.

A tie goes to the cheaper tier. The session reviews the routing, marks it, and
reports one line, such as `context sync: PROGRESS.md -> 2 knowledge, 1 finding`.

The ledger `.claude/context-sync.tsv` stores blob hashes and is committed, so a
team shares sync state and later sessions read only what changed. `check` also
flags:

- a knowledge file or skill with no INDEX row;
- a rule with no `paths:`;
- a skill whose description isn't a trigger;
- a findings entry worth promoting;
- a stale `LESSONS.md`;
- an outdated `CLAUDE.md` section.

Sources are the root `*.md` files and `docs/`.
`/context-sync sources add 'notes/*.md'` adds more. `/context-init` runs the
first ingest, both on a new repo and when refreshing an old one.
`/context-sync off` turns it off.

Where the plugin's hooks run, the session-start hook also runs the check and
tells the session whether anything changed, which saves a step; the section
works without it.

### PR trains

When an agreed plan holds two or more asks that would each be reviewed as
their own PR (a UI change plus a roles change, say), the `pr-train` skill
runs them as a train: one branch and one PR per task, built in dependency
order. State lives in a temporary file, `.claude/handoff/<slug>.md`, written
from `templates/handoff.md`. The directory carries its own `.gitignore` of
`*`, so it is never committed. The file records the goal, the repo's PR
conventions, a task checklist, a done log and mid-task state. Tasks whose
files don't overlap are built at the same time by subagents in isolated git
worktrees. Shared files (README, changelog, version manifests, lockfiles,
indexes) are applied afterwards, in task order, so branches never conflict.
After each PR or parallel batch, Claude updates the train file and asks you
to run `/compact`; it cannot compact itself. Resume needs no hook: the
managed PR train section of `CLAUDE.md` reloads after compaction and tells
the next session to read any train with `status: active` and continue from
its next unchecked task. Where the plugin's hooks run, the session-start hook
also points at the active train file; that is only a shortcut.
`/pr-train status` shows the task list. `/pr-train off` and `/pr-train on`
toggle the section.

### Turning it off

| Variable | Effect |
|---|---|
| `CONTEXT_KIT_OFF=1` | Disables every context-kit hook. |
| `CONTEXT_KIT_NO_SIGNALS=1` | Disables repeat detection and the activity ledger. |
| `CONTEXT_KIT_NO_ACTIVITY=1` | Disables the activity ledger only; repeat detection stays on. |
| `CONTEXT_KIT_LEVEL=<level>` | Overrides the lean level for one session. |

`/lean off` stops the ruleset injection but leaves the bootstrap and repeat
detection in place.

---

## Automatic skill capture

The one thing here that writes files on its own initiative.

When Claude finishes a procedure worth repeating, it writes the skill and
reports one line:

```
created: .claude/skills/deploy-staging/SKILL.md - fires on: deploy, staging, promote a build
```

No permission prompt. A new file under `.claude/skills/` is additive,
uncommitted, and one `git checkout` from gone — while a skill that needs
permission to exist mostly does not get created.

The cost is sprawl, so the filters do the work. It will not capture a one-off,
anything derivable from the code, anything an existing skill covers, a bare
single command, or anything it cannot write a trigger sentence for. It never
writes to `~/.claude/skills/`, and it never commits. Pruning is `/context-init cleanup`
(Mode B), which audits skills for near-duplicates and capability-shaped
descriptions that will never fire.

If the procedure needs a credential, it records the *name* of the variable and
where it comes from — never a value.

---

## The context graph

```
/context-graph              # build it
/context-graph serve        # ...and serve it at http://127.0.0.1:8848
/context-graph vault        # ...or write it as Obsidian notes
```

Writes `.claude/context-graph/graph.json` and a `graph.html` you open in a
browser. The HTML is **one self-contained file** — data inlined, nothing
fetched, no CDN — so it works over `file://` with the network off.
`scripts/check.sh` fails the build if an external reference ever appears in
it.

What it draws:

- **The static layout.** `CLAUDE.md`, each `.claude/rules/*.md` and the globs
  it claims, `knowledge/`, skills, commands, agents, findings — and the links
  between them.
- **The activity over it.** Which subagents were spawned, which files they
  read and wrote, which skills fired. A silent, capped, project-relative
  ledger written by the hooks; identifiers only, never arguments or content,
  and nothing outside the project is recorded.

Every edge is tagged `EXTRACTED` (a real link or frontmatter field),
`INFERRED` (a name matched in prose) or `OBSERVED` (from the ledger), so you
can tell what is written down from what was guessed from what merely
happened once on your machine.

What it flags, each with a specific fix:

| | |
|---|---|
| a rule whose `paths:` match nothing | it can never fire — and you believed it was covering something |
| a rule with `**/*` or no `paths:` | tier 1 in a tier-2 costume |
| knowledge nothing routes to | tier 3 is reached by lookup, so nothing will find it |
| a skill never invoked, or described as a capability | the description is the entire firing mechanism |
| a `SKILL.md` over 12KB with no `references/` | it all loads the moment the skill fires |
| tier 1 over 120 lines | paid on every session and every subagent |

`vault` exports one wikilinked note per node so Obsidian's own graph view
shows the same structure. **Pointing `--dir` at a vault you already use is
safe:** a manifest records what context-kit wrote, and any file it did not
create is never overwritten.

`serve` binds `127.0.0.1` and warns, specifically, before binding anything
wider. It serves with whatever the machine already has — `python3`, `php`,
`ruby`, `busybox` — installs nothing, and if none exist it just prints the
`file://` URL, because the page never needed a server.

Full detail in [docs/context-graph.md](docs/context-graph.md), including what
it deliberately does not measure.

---

## Blast radius

```bash
/blast-radius                        # no argument means --diff
/blast-radius --diff --base main     # everything on this branch
/blast-radius <symbol>               # a function, class or constant
/blast-radius <symbol> --file <path> # ...as defined in that one file
/blast-radius src/lib/auth.ts        # a path means --file
```

Walks the import graph **backwards** from the seed and reports what is
downstream, grouped by distance, with the importing line in each file. This is
real output, from `tests/fixtures/imports/go` and trimmed with `...`:

```
blast-radius: seeds=1 affected=12 depth=2 edges=27 gaps=0

## Seeds
internal/util/strings.go

## Depth 1
cmd/appsvc/dot_test.go:6 -> internal/util/strings.go
internal/config/config.go:8 -> internal/util/strings.go
...

## Depth 2
cmd/appsvc/main.go:16 -> internal/config/config.go
...

## Tests to run
cmd/appsvc/dot_test.go
cmd/appsvc/main_test.go
```

`--diff` is the mode for audits and debugging: it seeds from every changed
file at once — unstaged, staged **and untracked**, plus deleted files and the
old path of a rename, which is exactly where importers break; `--base REF`
diffs from the merge-base and includes uncommitted work. Untracked files are
in because a new file is the most common thing an audit adds and `git diff`
alone never mentions one.

The list is only where the work starts. The skill opens every depth-1 importer
and gives it a breaks, must-update, safe or unclear verdict, then runs the
"Tests to run". Blind spots count only actionable unresolved imports, and name
the unresolved specifiers that match a seed.

A managed "Blast radius" section in `CLAUDE.md` requires the skill before
structural edits: exported signatures; renaming, moving or deleting files or
exports; shared modules, schemas, config keys and routes.
`/context-init off blast-radius` turns it off.

**It is file-level, and the report never lets you forget it.** It follows
imports, so it cannot see runtime wiring — route tables, DI containers,
plugin registries, reflection, string-keyed factories — and it does not track
which function calls which. Every run prints that caveat, including the runs
where every import resolved cleanly, because a clean run is exactly when it
would otherwise read as complete.

Symbol mode separates resolved dependencies from bare name matches, since
"same name, unrelated symbol" is the common case and folding the two together
is how an impact report becomes fiction.

Resolution covers relative paths, `tsconfig*`/`jsconfig*` aliases from
**every** config in the repo (monorepos declare their own; create-vue keeps
`@/*` in `tsconfig.app.json`), a relative `extends` followed one level, literal
Vite `resolve.alias` entries, C# `using` namespaces matched to the files that
declare them, `go.mod` module prefixes from every module, composer PSR-4,
Python dotted and relative imports, Rust `mod`/`use`, JVM packages, C
`#include`, and the TypeScript ESM habit of writing `./x.js` for a file called
`x.ts`. Anything it cannot resolve uniquely is **dropped with a reason**, never
guessed — a wrong edge makes you stop looking, a missing one only makes you
look further.

Nine language families have a fixture under `tests/fixtures/imports/`
carrying the exact edge set `scripts/check.sh` asserts — 254 edges in all.
The fixture and an independent list of the edges it should produce were
written separately and then reconciled, and the traps are there on purpose:
imports inside Java text blocks, Kotlin raw strings, C++ raw strings, Ruby
heredocs, PHP nowdocs and JS template literals; `import ()`; a UTF-8 BOM;
CRLF; two statements on one line; a wrapped import; colliding basenames; and
a sibling module whose name is a prefix of the real one. That reconciliation
found thirteen real defects in the extractor, all fixed and each now pinned
by a fixture.

Detail, and the full list of what it cannot see, in
[docs/blast-radius.md](docs/blast-radius.md).

---

## The findings ledger

A finding that exists only in the transcript does not survive compaction.
Compaction summarizes, and the exact line, the exact number, and the dead end
you already ruled out are the first things a summary drops — which are
precisely the things you would otherwise re-derive.

```bash
/finding            # record what you just settled
/finding reflect    # roll every entry into findings/LESSONS.md
```

Entries are appended to `findings/<investigation>.md`, one file per
investigation, never overwritten. Each carries an **outcome** — `useful`,
`dead_end` or `corrected` — and the sources it leaned on. `reflect` then
aggregates every entry into `LESSONS.md`: preferred sources, tentative ones,
contested ones, known dead ends, corrections.

It is deterministic. No model, stable ordering, the same bytes for the same
input on the same day, and `--if-stale` makes it a no-op when nothing has
been appended — cheap enough to run at the start of every session.

Two rules keep it from lying to you:

- **One entry never mints a trusted source.** Two corroborating `useful`
  entries before anything is called preferred. One confident note is how a
  wrong answer becomes a fact.
- **Signals decay, 30-day half-life.** A dead end found last week outweighs a
  success from March. Without decay, a ledger grows more confident the more
  out of date it gets.

Both are tunable (`--min-corroboration`, `--half-life`).

---

## Lean execution

Absorbed from [ponytail](https://github.com/DietrichGebert/ponytail) (MIT), with
two additions it does not have. Full detail in
[docs/efficiency.md](docs/efficiency.md); exact provenance in [NOTICE](NOTICE).

The ladder — stop at the first rung that holds:

```
1. Does this need to exist?   -> no: skip it (YAGNI)
2. Already in this codebase?  -> reuse it, don't rewrite
3. Stdlib does it?            -> use it
4. Native platform feature?   -> use it
5. Installed dependency?      -> use it
6. One line?                  -> one line
7. Only then: the minimum that works
```

It runs *after* the problem is understood, never instead of it. The smallest
change in the wrong place is not lazy, it is a second bug.

Rung 4 has a lookup table: [`knowledge/platform-native.md`](knowledge/platform-native.md),
~180 rows mapping "the package you were about to install" to "the thing the
platform already ships" — HTML, CSS, browser APIs, SwiftUI, Node, Python, SQL,
.NET, and the pandas/Polars/DuckDB stack. It lives inside the plugin, not in
your repo, and loads only on lookup.

**The two additions:** locate before you read (grep for the symbol, then read
the ranges around the hits, rather than pulling a file whole), and delegate
fan-out searches to a subagent so raw tool output never enters the main window.
Those are the largest input-token levers and ponytail does not cover them.

**Never simplified away:** input validation at trust boundaries, error handling
that prevents data loss, security, accessibility, or anything you explicitly
asked for.

### No savings numbers

This plugin will not tell you how many lines or tokens it saved on your repo.
The version that was not built was never written, so there is no baseline to
subtract from, and a fabricated percentage is worse than none because it gets
quoted. `/context` and `/shortcut-ledger` produce real numbers. Use those.

---

## What's in the box

```
context-kit/
├── .claude-plugin/
│   ├── plugin.json              # plugin manifest
│   └── marketplace.json         # so this repo can be added as a marketplace
├── hooks/
│   ├── hooks.json               # SessionStart, SubagentStart, UserPromptSubmit, PostToolUse
│   ├── context-kit.sh           # POSIX sh entrypoint (session|subagent|mode|signal)
│   ├── context-kit.ps1          # PowerShell twin, same behavior
│   └── rules.md                 # the injected ruleset, level-tagged
├── commands/
│   ├── context-init.md          # /context-init
│   ├── context-graph.md         # /context-graph
│   ├── context-sync.md          # /context-sync
│   ├── blast-radius.md          # /blast-radius
│   ├── finding.md               # /finding
│   ├── skill-capture.md         # /skill-capture
│   ├── lean.md                  # /lean
│   ├── lean-review.md           # /lean-review
│   ├── model-routing.md         # /model-routing
│   ├── pr-train.md              # /pr-train
│   ├── shortcut-ledger.md       # /shortcut-ledger
│   └── context-help.md          # /context-help
├── skills/
│   ├── context-cleanup/         # the scaffold, refresh and audit skill
│   │   └── references/          # modes A, R and B, loaded only when chosen
│   ├── context-graph/           # reads graph.json and says what to cut
│   ├── context-sync/            # the session-start sync
│   │   └── references/          # routing rules, read only when something changed
│   ├── blast-radius/            # impact analysis, and how far to trust it
│   │   └── references/          # reading-output.md, loaded when the report needs reading
│   ├── finding-ledger/          # the working log and its lessons
│   ├── skill-capture/           # writes new skills
│   ├── lean-execution/          # the long-form ruleset
│   ├── lean-review/             # what can be deleted
│   ├── pr-train/                # split a plan into PRs, resume across /compact
│   │   └── references/          # the parallel-lane prompt, loaded only for a batch
│   └── shortcut-ledger/         # the debt ledger
├── knowledge/
│   └── platform-native.md       # tier-3 reference, loads on lookup only
├── scripts/
│   ├── check.sh                 # self-check: versions, filenames, hook output
│   ├── context-graph.sh         # build | serve | vault | open
│   ├── code-graph.sh            # the file-level import graph
│   ├── code-graph.awk           # import extraction and path resolution
│   ├── blast-radius.sh          # what breaks if this changes
│   ├── blast-radius.awk         # the reverse traversal
│   ├── context-graph.awk        # the layout scanner and analyzer
│   ├── context-vault.awk        # graph.json -> an Obsidian vault
│   ├── findings.sh              # record | reflect
│   ├── findings.awk             # the deterministic lessons aggregator
│   ├── context-sync.sh          # check | diff | mark | sources
│   └── claude-sections.sh       # status | stamp | off | on: the managed CLAUDE.md sections
├── docs/
│   ├── three-tier-model.md      # the model, and why it is shaped this way
│   ├── context-graph.md         # what the graph holds and what it flags
│   ├── blast-radius.md          # the file-level trade, and its blind spots
│   ├── efficiency.md            # the absorbed ruleset and its reasoning
│   ├── authoring.md             # how to write each tier well
│   ├── adoption.md              # rolling it into a repo that already exists
│   └── anti-patterns.md         # the failure modes, and what they look like
├── tests/
│   ├── checks/                  # per-feature suites sourced by check.sh
│   └── fixtures/imports/        # one per language, with its expected edges
└── templates/
    ├── graph/viewer.html        # the offline, dependency-free graph viewer
    ├── sections/                # the managed CLAUDE.md sections, one file each
    ├── CLAUDE.template.md       # a starting tier-1 file
    ├── handoff.md               # the PR train file, copied to .claude/handoff/
    ├── rules/example-rule.md    # a tier-2 rule with correct frontmatter
    ├── knowledge/INDEX.md       # the tier-3 index
    └── findings/README.md       # the compaction-survival convention
```

Run `sh scripts/check.sh` after changing anything: it catches version drift
between the manifests, uppercase `SKILL.MD`, descriptions written as
capabilities rather than triggers, and hooks that stopped emitting valid JSON
or stopped failing open.

---

## Why bother

Five failure modes this is built against:

1. **`CLAUDE.md` accumulates.** Every session that learns something adds a
   line. Nothing ever removes one. Adherence to the whole file degrades as it
   grows, so the newest entries quietly weaken the oldest.
2. **Knowledge goes stale silently.** A count, a version, a port number in
   tier 1 is asserted on every task until someone notices it is wrong. By then
   several decisions have been made on top of it.
3. **Findings die in compaction.** Analysis that only exists in the transcript
   does not survive a long session. Appended to a file, it does.
4. **The same procedure gets re-derived every time.** Nobody writes the skill,
   because writing the skill is a separate task nobody assigns.
5. **The layout rots invisibly.** A rule whose `paths:` stopped matching
   anything, a knowledge file nothing links to, a skill whose description
   never fires — none of these produce an error. They produce silence, which
   reads exactly like working.

The layout addresses 1 structurally, `findings/` and `/finding` address 3,
`skill-capture` addresses 4, and `/context-graph` addresses 5 by making the
silence visible. For 2, see the staleness section in
[docs/anti-patterns.md](docs/anti-patterns.md) — the honest answer is that a
hook beats a request.

## Extending this

This repo grows by absorbing patterns from other projects. When you find one:

- A **conditional** rule that generalizes → add it to `templates/rules/`.
- A **repeatable procedure** → a new skill under `skills/`.
- A **failure mode** you hit twice → a section in `docs/anti-patterns.md`.
- A **package that the platform already covers** → a row in
  `knowledge/platform-native.md`.
- A **layout defect you can detect mechanically** → a finding in
  `scripts/context-graph.awk`, and a row in the table in
  [docs/context-graph.md](docs/context-graph.md).

Keep the bar high. Anything added here loads into real projects, so it is
subject to the same classification test as the knowledge it organizes.

## License

MIT. See [LICENSE](LICENSE).

Two projects were absorbed, neither as a dependency: **ponytail** (MIT) for the
lean execution ruleset, and **graphify** (Apache-2.0, Graphify Labs) for the
graph's edge-confidence model, the Obsidian export and its ownership rule, the
work-memory aggregation behind `/finding`, and the split-skill layout.
[NOTICE](NOTICE) lists exactly what was taken from each — and, for graphify,
what was deliberately left behind and why.

graphify is a different tool answering a different question: if you want a
queryable map of a large *codebase*, with cross-file call graphs across forty
languages, use graphify. The two run happily side by side.
