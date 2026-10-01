# Routing: what the sync subagent does

You were given lines from `context-sync.sh check` and the plugin root, called
`<root>` below. Your job is to move what is new in project markdown into the
cheapest place that still gets it used, and to fix the layout gaps the lines
name. You write files in the working tree. You do not commit, you do not run
`mark` (the caller does, after reviewing your table), and you never write to
`CLAUDE.md`.

## Before you route anything

1. Read `knowledge/INDEX.md`, list `knowledge/`, `.claude/rules/` and
   `.claude/skills/`, and read the `description` of each rule and skill. You
   are looking for what already says what you are about to write.
2. If INDEX.md has no table yet, read `<root>/templates/knowledge/INDEX.md` for
   the router format: a "Read it when" column that states a condition.
3. Before writing a rule, read `<root>/templates/rules/example-rule.md`.

## For each `source` or `findings` line

Run `sh <root>/scripts/context-sync.sh diff <path>` and read only what it shows.
A `gone` source needs no diff: remove the INDEX row that points at it, if any.
The diff of a new file is the whole file; open the file for the surroundings
only when a hunk is unclear.

Split what is new into items, and place each one with the table below. The
test is the one in `context-cleanup`: would missing this make an unrelated
task go wrong? Almost never. When undecided, take the cheaper place, a
knowledge file over a rule and leaving it in its source over copying it: a
wrong high placement taxes every session, a wrong low one costs one visible
mistake. Say which rows were close calls in your table.

| What the item is | Where it goes |
|---|---|
| A durable fact about how it works now | `knowledge/<topic>.md`, plus an INDEX row |
| A decision with its reasoning, a dead end, a measured result, a correction | `findings/<topic>.md`, through `findings.sh record` |
| A convention that applies when certain files are touched | `.claude/rules/<topic>.md` with a narrow `paths:` list and a `description` |
| A repeatable multi-step procedure | a project skill, by `<root>/skills/skill-capture/SKILL.md` |
| Status, todo lists, undecided ideas, anything derivable from the code | stays where it is |

- **Knowledge.** One topic per file, named for the words someone would search
  for. Append a section to an existing topic file rather than starting a near
  duplicate. Split a file that passes about 300 lines. Every file gets an INDEX row.
- **Findings.** `findings.sh record` is the only writer of findings entries:
  `sh <root>/scripts/findings.sh record --file <topic> --question Q --finding F
  --outcome useful|dead_end|corrected --confidence confirmed|inferred|unverified
  --sources "<file> (synced YYYY-MM-DD)"`. Never edit a findings file by hand.
- **Rules.** `paths:` as narrow as the convention applies; `**/*` is not narrow.
- **Stays in its source.** Do not copy a status log or a todo list. Give the
  source one INDEX row under "The record" instead: `Read <file> when <what
  question it answers>`. Do the same when the source is itself the authoritative
  record (a spec, an ADR, an agreement): point at it, do not copy it.
- **A `findings changed` entry** that is now durable (Outcome useful,
  Confidence confirmed, and still true when you check the code or doc it names)
  is promoted to `knowledge/`. The finding stays where it is.

Every entry you write ends with `Source: <file> (synced YYYY-MM-DD)`, using
today's absolute date. A finding carries it in `--sources`. Before writing,
search the target for that `Source:` line and for the claim itself; skip
anything already said, so syncing twice never duplicates. If a claim in the
target is contradicted by the source, append the correction, do not rewrite it.
Never copy a credential, token or connection string: name the variable and
where it comes from.

## For the other lines

- `index missing <path>`: add the INDEX row for that knowledge file or skill,
  with a "Read it when" condition read from the file.
- `rule no-paths <path>`: read the rule and add a narrow `paths:` list derived
  from what it is about. If it truly applies everywhere, say so in your table
  instead of guessing; it may belong in CLAUDE.md, which only the user changes.
- `skill no-trigger <path>`: rewrite the `description` so it starts "Use when"
  and names the situations and the words of a real request, then when not to fire.

## Return

A table, one row per routed item, and nothing else but the path list:

```
source -> target : one-line summary
PROGRESS.md -> knowledge/auth.md : token refresh now runs in the gateway
PROGRESS.md -> stays : status log; INDEX row added
docs/IDEAS.md -> findings/search-ranking.md : BM25 tried, dead end
```

Then `processed:` and every `source` and `findings` path you handled, one per
line, including ones where you decided nothing needed copying: the caller marks
exactly those. Leave out a path you could not finish.
