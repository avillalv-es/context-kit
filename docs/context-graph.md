# The context graph

`/context-graph` draws the context layout and tells you what is wrong with it.

It does **not** index your code. That distinction is the whole design, so it
is worth being precise about: code structure is already in the code, and an
agent can read it. What no agent can read is which of your tier-2 rules will
never fire, which knowledge file nothing routes to, and which skill has never
once been invoked. Those are properties of the *wiring*, not of any one file,
and they are invisible until you draw them.

---

## What it reads

| Source | Becomes |
|---|---|
| `CLAUDE.md`, `AGENTS.md` | the `tier1` node, with its real line count |
| `.claude/rules/*.md` | a `rule` node per file, plus a `path` node per `paths:` glob |
| `knowledge/*.md` | `knowledge` nodes |
| `.claude/skills/*/SKILL.md` | `skill` nodes, carrying the description that fires them |
| `.claude/commands/`, `.claude/agents/` | `command` and `agent` nodes |
| `findings/*.md` | `finding` nodes |
| the activity ledger | `session` nodes, and the files, skills and agents they touched |

The bare directory names (`rules/`, `knowledge/`, `skills/`, `commands/`) are
scanned too, so the plugin's own source tree graphs as readily as a project
that installed it.

Globs are resolved against `git ls-files` where there is a work tree, and a
filtered `find` otherwise. Using git's list matters: it already honours
`.gitignore`, so `node_modules` never inflates a rule's apparent reach.

## What it writes

```
.claude/context-graph/
├── graph.json     nodes, edges, findings   ← read this
├── graph.html     the viewer                ← open this
└── vault/         one wikilinked note per node (only on `vault`)
```

Add `.claude/context-graph/` to `.gitignore`. It is derived, it changes on
every build, and committing it turns every session into a diff.

## The edges, and how much to trust them

Every edge carries a tag saying how it was learned. This is the one idea
taken wholesale from graphify, and it is the right one: the difference
between "this link is written down" and "I matched a word in prose" belongs
at the point of use, not in a footnote.

| Relation | What it means | Tag |
|---|---|---|
| `routes_to` | one context file links to another | `EXTRACTED` (markdown link) or `INFERRED` (backticked path) |
| `covers` | a rule's `paths:` glob, with its real match count | `EXTRACTED` |
| `cites` | the layout points at an ordinary repo doc as its authority | `EXTRACTED` (markdown link) or `INFERRED` (backticked path) |
| `mentions` | a file names a skill or command in backticks or as `/command` | `INFERRED` |
| `spawned`, `used`, `read`, `wrote` | recorded activity | `OBSERVED` |

A `CLAUDE.md` routing table almost always writes `` `.claude/rules/x.md` ``,
not `[x](.claude/rules/x.md)` — a markdown link is the exception, not the
rule. Both are extracted, and both resolve to the same real paths: layout
files and ordinary repo files, project-root and directory-relative. The
confidence tag is the only difference, and it is a real one: a link is
unambiguous syntax that promises a reference; a backtick span is formatting
that usually does but does not have to.

`INFERRED` matches on an exact backticked token or a full path, never a
substring, so `` `lean-review` `` does not also register as a mention of
`lean`, and `` `units.ts` `` does not match `src/lib/units.ts` unless the
token names the whole path. It can still be wrong — prose is prose.

`OBSERVED` is a record of what happened on *one machine*, not a property of
the repo. Two people will have different activity layers over the same
layout. Never treat an absence there as evidence about the repo.

## What it flags

Each of these is a concrete defect with a concrete fix, not a code smell.

| Finding | Why it matters |
|---|---|
| `paths:` match no file | the rule cannot fire. It is pure weight, and worse, you believe it is covering something |
| `paths:` match the whole tree | tier 1 in a tier-2 costume: paid on every session, with none of tier 1's scrutiny |
| no `paths:` at all | the same thing, by omission rather than by `**/*` |
| nothing routes here | tier 3 is reached by lookup. Nothing links it, so nothing will find it |
| never invoked | either nobody needed it, or the description does not match how anyone asks |
| description is not a trigger | "helps with X" matches nothing. The description is the entire firing mechanism |
| `SKILL.md` over 12KB | it all loads the moment the skill fires. Split the lookup half into `references/` |
| tier 1 over 120 lines | paid on every session and every subagent, forever |

The "never invoked" finding is suppressed when the activity ledger is empty,
because "no record" and "never used" are different claims.

## The viewer

One file, data inlined, nothing fetched. It opens over `file://` with the
network off, which is the point on an air-gapped machine —
`scripts/check.sh` fails the build if a `src=`, `href=`, `fetch(` or an
`http` URL ever appears in it.

Drawn on a canvas with a plain repulsion-and-spring layout. O(n²), which is
free at the size a context layout actually reaches; a quadtree here would be
rung-1 work on a problem nobody has.

Node colour is the kind, size is degree, a warning ring means a finding.
Click a node to inspect it. Click a legend row to hide that kind. The
starting positions are derived from the node index rather than randomly
seeded, so the same graph opens looking the same twice running.

## `serve`

```bash
/context-graph serve            # http://127.0.0.1:8848/graph.html
```

Loopback by default. Binding anything else prints a warning first, and the
warning is specific about what leaks: file paths, rule names, skill
descriptions and recorded activity. There is no authentication and there
should not be — the right answer for remote access is an SSH tunnel, not a
password field in a graph viewer.

It serves with whatever the machine already ships (`python3`, `python`,
`php`, `ruby`, `busybox`) and installs nothing. If none of them exist it
prints the `file://` URL and exits, because the page never needed a server
in the first place.

## `vault`

```bash
/context-graph vault --dir ~/vaults/my-project
```

One note per node, `[[wikilinked]]`, with kind tags in frontmatter and a
`_MAP.md` index. Obsidian's own graph view then shows the same structure.

**Pointing this at a vault you already use is safe.** A manifest records
every note context-kit wrote; a file that exists in the target but is not in
the manifest is yours and is never touched. The run reports what it skipped.
That rule is inherited from graphify, which learned it by overwriting
people's notes.

Glob nodes are the one thing that gets no note. `src/api/**` makes a filename
no filesystem wants and a title no reader gains from; what matters about a
glob is how many files it matches, and that is printed inside the rule that
claims it.

## The code layer

`--code` adds a second layer: the modules of the codebase and the imports
between them, from `scripts/code-graph.awk`. Same graph, same viewer.

```bash
/context-graph --code
/context-graph --code-cap 300     # draw more modules
```

It is **capped**, by fan-in, at 120 modules by default. A real application
has thousands of source files, and drawing all of them produces a hairball
that answers nothing. What the layout graph is for is showing which modules
everything flows through. `/blast-radius` reads the full, uncapped edge list
separately — the cap is a display decision, not a data one.

The layer earns its place through one finding that needs **both** layers, and
that neither grep nor a code index can produce alone:

> *N files import this and no rule covers it.*

A module with high fan-in and no tier-2 rule is a module everything leans on
with no conventions written down. Finding it requires knowing the import
graph *and* knowing which paths each rule's `paths:` glob claims. Nothing
else in either tool has both halves.

Full detail on the extractor, what it resolves and what it drops, is in
[blast-radius.md](blast-radius.md).

## What it will not tell you

A token or percentage saving. The graph counts nodes, edges, lines and glob
match counts, and those are real numbers you can check. "40% smaller context"
is not, because the version that was never loaded has no baseline to subtract
from — and a fabricated figure is worse than none, because it gets quoted.

## Turning the activity layer off

| Variable | Effect |
|---|---|
| `CONTEXT_KIT_NO_ACTIVITY=1` | stop recording activity; the static layout still graphs |
| `CONTEXT_KIT_NO_SIGNALS=1` | stop both the activity ledger and repeat detection |
| `CONTEXT_KIT_OFF=1` | stop every context-kit hook |

The ledger records identifiers only — a tool name, a project-relative file
path, a skill name, a subagent type. Never arguments, never file contents,
never prompt text. Paths outside the project are dropped rather than
recorded. It lives under `$CLAUDE_PLUGIN_DATA` (default
`~/.claude/context-kit/`), not in the repo, and it is capped and rotated.
