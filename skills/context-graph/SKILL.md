---
name: context-graph
description: Use when the user asks to see, visualize, serve or map the context layout, asks for a graph or dashboard of CLAUDE.md, rules, skills, knowledge and agents, asks which rules never fire or what knowledge nothing links to, asks to see what the agents and subagents have been touching, wants an Obsidian vault of the layout, or runs /context-graph. Do not use for indexing source code or building a code call graph - this maps the context layout, not the codebase.
---

# Context graph

Render the context layout as a graph and read what it says. The layout is the
one thing about a repo an agent cannot see by reading the code: which rule
will never fire, which knowledge nothing routes to, which skill has never
once been invoked. Those are properties of the wiring, and they only show up
when you draw it.

This does **not** index source code. Code structure is in the code and you
can read it. Running a parser over the codebase to rediscover what a grep
would tell you is the thing this plugin exists to argue against.

## Run it

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/context-graph.sh" build
```

Other modes — `serve` (adds a URL), `vault` (Obsidian notes), `open`. Pass
the user's flags straight through. `serve` binds `127.0.0.1` and blocks; run
it in the background and report the URL rather than waiting on it.

Output lands in `.claude/context-graph/`:

| File | What it is |
|---|---|
| `graph.json` | nodes, edges, and the findings — read this, not the HTML |
| `graph.html` | the viewer. Self-contained, opens over `file://`, no network |
| `vault/` | one wikilinked note per node, only on `vault` |

Read `graph.json`. Never read `graph.html` — it is the same data wrapped in
20KB of viewer you already know the behaviour of.

## What the graph holds

**Nodes.** `tier1` (CLAUDE.md), `rule` (tier 2), `path` (a glob a rule
claims), `knowledge` and `skill` (tier 3), `command`, `agent`, `finding`,
`doc` (a repo file the layout cites), `file` (touched during a session),
`session`, `hook`.

**Edges,** each carrying a confidence tag:

| Relation | Means | Confidence |
|---|---|---|
| `routes_to` | one context file links to another | `EXTRACTED` |
| `covers` | a rule's `paths:` glob, and how many files it matches | `EXTRACTED` |
| `cites` | the layout points at an ordinary repo doc as its authority | `EXTRACTED` |
| `mentions` | a file names a skill or command out loud | `INFERRED` |
| `spawned` / `used` / `read` / `wrote` | recorded activity | `OBSERVED` |

`EXTRACTED` was read from a link or a frontmatter field. `INFERRED` was
matched from prose. `OBSERVED` came from the activity ledger and is a record
of one machine's sessions, not a property of the repo. Say which you are
relying on; do not present an `INFERRED` edge as a fact.

## Reading it

Work the `issues` array first — each one is a concrete, fixable defect:

| Finding | What it means | The fix |
|---|---|---|
| paths match no file | the rule cannot fire, ever | fix the glob, or delete the rule |
| paths match the whole tree | tier 1 in a tier-2 costume, paid every session | narrow it, or move the content to tier 1 honestly |
| no `paths:` frontmatter | same, by omission | add `paths:` |
| nothing routes here | tier 3 is reached by lookup only, so nothing will find it | link it from the tier-3 index, or delete it |
| never invoked | either nobody needed it, or the description does not match how people ask | rewrite the description as a trigger, or delete |
| description is not a trigger | "helps with X" matches nothing | rewrite as "Use when…" |
| SKILL.md over 12KB | the whole file loads when it fires | split the reference half into `references/` |
| tier 1 over 120 lines | paid on every session and every subagent | `/context-init cleanup` (Mode B) |

Then look for what the findings cannot catch:

- **A hub with no inbound edges.** High degree, nothing points at it. Usually
  a doc doing tier-1 work from tier 3.
- **Two skills covering one trigger.** Both fire, or neither does predictably.
- **A rule citing no authority.** No `cites` edge means nobody can find out
  why the rule exists, so it gets ignored the first time it is inconvenient.
- **Files touched in every session that no rule covers.** The `OBSERVED` layer
  next to the `covers` layer: an area people work in constantly with no
  conventions written down.

## Reporting

Findings only, one line each, biggest cut first. Do not edit the layout
unless the user asks — moving knowledge is where it gets silently lost, which
is why `/context-init cleanup` (Mode B) stops and shows a table first.

Do not quote a token or percentage saving. The graph counts nodes, edges,
lines and match counts; those are real. A "40% smaller context" is not,
because the version that was never loaded has no baseline to subtract from.

## When the activity layer is empty

No `session` nodes means the hooks have not run in this project yet, or
`CONTEXT_KIT_NO_ACTIVITY=1` is set. Say so. Do not read "never invoked" as
evidence against a skill when nothing was recorded in the first place — the
builder already suppresses that finding when the ledger is empty, and you
should not reintroduce it by eye.
