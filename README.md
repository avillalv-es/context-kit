# context-kit

A three-tier context layout for Claude Code projects, packaged as a plugin.

The premise: **every line in `CLAUDE.md` is a tax on every session and every
subagent, forever.** Knowledge that only matters when you touch the database
should not be loaded when you are editing a stylesheet. This repo holds the
command, the skill, the templates and the authoring standards for putting each
piece of knowledge in the cheapest tier that still guarantees it gets used.

It is deliberately **not** a retrieval tool. It does not index your code, build
a graph, or embed anything. Code structure is already in the code, and a good
agent can read it. What an agent cannot read is *why* a column is nullable on
purpose, or which of two contradictory requirements is the live one. That is
what this organizes.

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

The full reasoning, including why the error costs are asymmetric, is in
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

As a plugin, from this repo:

```bash
claude
```

Then, inside Claude Code:

```
/plugin marketplace add avillalv-es/context-kit
/plugin install context-kit@context-kit
```

Or copy the two pieces in by hand:

```bash
cp -r skills/context-cleanup ~/.claude/skills/
cp commands/context-init.md ~/.claude/commands/
```

Use `~/.claude/` for every project, or `<repo>/.claude/` for one.

> **Filename note.** The skill file must be `SKILL.md` — lowercase `.md`.
> `SKILL.MD` resolves on Windows and macOS but is silently invisible on a
> case-sensitive filesystem, which is where most containers and CI runners
> live. Same for the command: the filename becomes the command name, so
> `context-init.md` gives you `/context-init`.

## Use

```
/context-init
```

The skill picks its own mode:

- **Mode A — Initialize.** No `CLAUDE.md`, or one without a
  `## Context layout` section. Scaffolds the layout and adopts any existing
  content into it.
- **Mode B — Cleanup.** The layout already exists. Audits and rebalances it.

Mode B **stops and shows you a table before moving anything**, and does not
proceed on implied approval. That is deliberate: this is the step where
knowledge gets silently lost if you let it run unattended.

Pass extra instructions straight through:

```
/context-init only audit, do not propose moves yet
```

Restart the session afterwards and run `/context` to see the real number.

---

## What's in the box

```
context-kit/
├── .claude-plugin/
│   ├── plugin.json           # plugin manifest
│   └── marketplace.json      # so this repo can be added as a marketplace
├── commands/
│   └── context-init.md       # the /context-init command
├── skills/
│   └── context-cleanup/
│       └── SKILL.md          # the two-mode audit + scaffold skill
├── docs/
│   ├── three-tier-model.md   # the model, and why it is shaped this way
│   ├── authoring.md          # how to write each tier well
│   ├── adoption.md           # rolling it into a repo that already exists
│   └── anti-patterns.md      # the failure modes, and what they look like
└── templates/
    ├── CLAUDE.md             # a starting tier-1 file
    ├── rules/example-rule.md # a tier-2 rule with correct frontmatter
    ├── knowledge/INDEX.md    # the tier-3 index
    └── findings/README.md    # the compaction-survival convention
```

## Why bother

Three failure modes this is built against, all of which cost real rework:

1. **`CLAUDE.md` accumulates.** Every session that learns something adds a
   line. Nothing ever removes one. Adherence to the whole file degrades as it
   grows, so the newest entries quietly weaken the oldest.
2. **Knowledge goes stale silently.** A count, a version, a port number in
   tier 1 is asserted on every task until someone notices it is wrong. By then
   several decisions have been made on top of it.
3. **Findings die in compaction.** Analysis that only exists in the transcript
   does not survive a long session. Appended to a file, it does.

The layout addresses 1 and 3 structurally. For 2, see the staleness section in
[docs/anti-patterns.md](docs/anti-patterns.md) — the honest answer is that a
hook beats a request.

## Extending this

This repo is meant to grow by absorbing patterns from other projects. When you
find one worth keeping:

- A **conditional** rule that generalizes → add it to `templates/rules/`.
- A **repeatable procedure** → a new skill under `skills/`.
- A **failure mode** you hit twice → a section in `docs/anti-patterns.md`.

Keep the bar high. Anything added here loads into real projects, so it is
subject to the same classification test as the knowledge it organizes.

## License

MIT. See [LICENSE](LICENSE).
