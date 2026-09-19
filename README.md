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

It is deliberately **not** a retrieval tool. It does not index your code, build
a graph, or embed anything. Code structure is already in the code, and a good
agent can read it. What an agent cannot read is *why* a column is nullable on
purpose, or which of two contradictory requirements is the live one.

---

## What it does

| | |
|---|---|
| **Bootstraps itself** | First session in a repo with no `## Context layout` block, Claude creates or appends one — as a visible diff you can decline. Offered once, then never again. |
| **Injects a lean ruleset** | ~30 lines into every session *and every subagent*: reuse before writing, locate before reading, answer before explaining. |
| **Captures skills on its own** | Finish a procedure worth repeating and Claude writes `.claude/skills/<name>/SKILL.md` and tells you in one line. No permission prompt, no ceremony. |
| **Detects repeats** | A silent ledger counts shell commands. Three runs of the same procedure with no skill covering it, and the next session says so. |
| **Audits the layout** | `/context-init` classifies every line of `CLAUDE.md` and shows you a table before moving anything. |

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

---

## Use

| Command | What it does |
|---|---|
| `/context-init` | Set up or rebalance the layout. Picks its own mode. |
| `/context-init bootstrap` | Scaffold and stamp the marker only. No survey. |
| `/skill-capture` | Turn a repeatable procedure into a project skill. |
| `/lean lite\|full\|ultra\|off` | Set the execution level. Persists across sessions. |
| `/lean-review [--repo]` | What can be deleted. Diff by default, whole tree with `--repo`. |
| `/shortcut-ledger` | Every deliberate shortcut marked in this repo. |
| `/context-help` | The reference card. |

`/context-init` picks its own mode:

- **Mode 0 — Bootstrap.** Scaffold and stamp the marker. Cheap, idempotent, no
  judgment. This is what the hook triggers automatically.
- **Mode A — Initialize.** No `CLAUDE.md`, or one without a `## Context layout`
  section. Surveys the repo and adopts existing content into the layout.
- **Mode B — Cleanup.** The layout exists. Audits and rebalances it, including
  `.claude/skills/`.

Mode B **stops and shows you a table before moving anything**, and does not
proceed on implied approval. That is deliberate: this is the step where
knowledge gets silently lost if you let it run unattended.

Pass extra instructions straight through:

```
/context-init only audit, do not propose moves yet
```

Restart the session afterwards and run `/context` to see the real number.

### Turning it off

| Variable | Effect |
|---|---|
| `CONTEXT_KIT_OFF=1` | Disables every context-kit hook. |
| `CONTEXT_KIT_NO_SIGNALS=1` | Disables repeat detection only. |
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
writes to `~/.claude/skills/`, and it never commits. Pruning is `/context-init`
Mode B, which audits skills for near-duplicates and capability-shaped
descriptions that will never fire.

If the procedure needs a credential, it records the *name* of the variable and
where it comes from — never a value.

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
│   ├── skill-capture.md         # /skill-capture
│   ├── lean.md                  # /lean
│   ├── lean-review.md           # /lean-review
│   ├── shortcut-ledger.md       # /shortcut-ledger
│   └── context-help.md          # /context-help
├── skills/
│   ├── context-cleanup/         # the three-mode scaffold + audit skill
│   ├── skill-capture/           # writes new skills
│   ├── lean-execution/          # the long-form ruleset
│   ├── lean-review/             # what can be deleted
│   └── shortcut-ledger/         # the debt ledger
├── knowledge/
│   └── platform-native.md       # tier-3 reference, loads on lookup only
├── scripts/
│   └── check.sh                 # self-check: versions, filenames, hook output
├── docs/
│   ├── three-tier-model.md      # the model, and why it is shaped this way
│   ├── efficiency.md            # the absorbed ruleset and its reasoning
│   ├── authoring.md             # how to write each tier well
│   ├── adoption.md              # rolling it into a repo that already exists
│   └── anti-patterns.md         # the failure modes, and what they look like
└── templates/
    ├── CLAUDE.template.md       # a starting tier-1 file
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

Four failure modes this is built against:

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

The layout addresses 1 and 3 structurally, and `skill-capture` addresses 4. For
2, see the staleness section in
[docs/anti-patterns.md](docs/anti-patterns.md) — the honest answer is that a
hook beats a request.

## Extending this

This repo grows by absorbing patterns from other projects. When you find one:

- A **conditional** rule that generalizes → add it to `templates/rules/`.
- A **repeatable procedure** → a new skill under `skills/`.
- A **failure mode** you hit twice → a section in `docs/anti-patterns.md`.
- A **package that the platform already covers** → a row in
  `knowledge/platform-native.md`.

Keep the bar high. Anything added here loads into real projects, so it is
subject to the same classification test as the knowledge it organizes.

## License

MIT. See [LICENSE](LICENSE). Material absorbed from ponytail is MIT as well;
attribution and the full list of what was taken is in [NOTICE](NOTICE).
