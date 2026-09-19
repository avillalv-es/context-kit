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

There is one graph here, and it is not of your code. `/context-graph` draws the
*context layout* — the tiers, the rules, the globs they claim, the skills, and
who touched what — because that is the part nothing else can see. A rule whose
`paths:` match no file is invisible in every view except this one.

---

## What it does

| | |
|---|---|
| **Bootstraps itself** | First session in a repo with no `## Context layout` block, Claude creates or appends one — as a visible diff you can decline. Offered once, then never again. |
| **Injects a lean ruleset** | ~30 lines into every session *and every subagent*: reuse before writing, locate before reading, answer before explaining. |
| **Captures skills on its own** | Finish a procedure worth repeating and Claude writes `.claude/skills/<name>/SKILL.md` and tells you in one line. No permission prompt, no ceremony. |
| **Detects repeats** | A silent ledger counts shell commands. Three runs of the same procedure with no skill covering it, and the next session says so. |
| **Audits the layout** | `/context-init` classifies every line of `CLAUDE.md` and shows you a table before moving anything. |
| **Draws the layout** | `/context-graph` renders tiers, rules, skills and recorded agent activity as a graph you open in a browser, and names the rules that can never fire. |
| **Remembers what was settled** | `/finding` logs a conclusion, a dead end or a correction; `reflect` aggregates them into `LESSONS.md` so a long investigation survives compaction. |

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
| `/context-graph` | Draw the layout. `serve` for a URL, `vault` for Obsidian notes. |
| `/finding` | Record a finding; `/finding reflect` rolls them into `LESSONS.md`. |
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
writes to `~/.claude/skills/`, and it never commits. Pruning is `/context-init`
Mode B, which audits skills for near-duplicates and capability-shaped
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
│   ├── finding.md               # /finding
│   ├── skill-capture.md         # /skill-capture
│   ├── lean.md                  # /lean
│   ├── lean-review.md           # /lean-review
│   ├── shortcut-ledger.md       # /shortcut-ledger
│   └── context-help.md          # /context-help
├── skills/
│   ├── context-cleanup/         # the three-mode scaffold + audit skill
│   │   └── references/          # modes A and B, loaded only when chosen
│   ├── context-graph/           # reads graph.json and says what to cut
│   ├── finding-ledger/          # the working log and its lessons
│   ├── skill-capture/           # writes new skills
│   ├── lean-execution/          # the long-form ruleset
│   ├── lean-review/             # what can be deleted
│   └── shortcut-ledger/         # the debt ledger
├── knowledge/
│   └── platform-native.md       # tier-3 reference, loads on lookup only
├── scripts/
│   ├── check.sh                 # self-check: versions, filenames, hook output
│   ├── context-graph.sh         # build | serve | vault | open
│   ├── context-graph.awk        # the layout scanner and analyzer
│   ├── context-vault.awk        # graph.json -> an Obsidian vault
│   ├── findings.sh              # record | reflect
│   └── findings.awk             # the deterministic lessons aggregator
├── docs/
│   ├── three-tier-model.md      # the model, and why it is shaped this way
│   ├── context-graph.md         # what the graph holds and what it flags
│   ├── efficiency.md            # the absorbed ruleset and its reasoning
│   ├── authoring.md             # how to write each tier well
│   ├── adoption.md              # rolling it into a repo that already exists
│   └── anti-patterns.md         # the failure modes, and what they look like
└── templates/
    ├── graph/viewer.html        # the offline, dependency-free graph viewer
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
