---
description: One line, written as a trigger — what this covers and when it applies. This string is what a reader sees before deciding to open the file.
paths:
  - "src/api/**"
  - "src/db/**"
  - "migrations/**"
---

<!--
  Tier-2 template. Copy to <repo>/.claude/rules/<domain>.md and rename.

  The filename is the domain, not the session. `database-schema.md`, not
  `schema-work-oct.md`. Before creating a new file here, check whether an
  existing rule already covers this area and add to it instead.

  `paths` is the entire cost-control mechanism. Scope it as narrowly as the
  knowledge genuinely applies. A missing `paths` field, or `**/*`, means this
  file loads on every session — which makes it tier 1 with none of tier 1's
  scrutiny.
-->

# <Domain> rules

Authority: `docs/<the-doc>.md` §N–§M. If you need to break one of these,
change the doc in the same commit and say why.

<!--
  The authority line matters more than it looks. It does two things: it tells
  a reader where the decision was actually made, and it gives a legitimate
  path to deviate. A rule with no escape hatch gets quietly ignored the first
  time it is inconvenient, and you never find out.
-->

## <Grouping — e.g. Naming>

- <The rule, stated as an instruction.> <Why, if the reason is not obvious.>
- **<Rule with a non-obvious failure mode.>** <What breaks if ignored.>

## <Grouping — e.g. Errors and logging>

- <Rule.>

## What must not change without a decision

<!--
  Optional, but this is where a rules file earns its place. List the things
  someone would reasonably "tidy" and must not. State the consequence, because
  a prohibition without a consequence reads as a preference.
-->

- **<The thing.>** <Why it is that way, and what tidying it would destroy.>

## Checkable by grep

<!--
  Optional. If a rule is mechanically checkable, say so and give the command.
  If several rules here are checkable, that is a signal they should be a hook
  or a test instead of prose — a guarantee costs no context until it fires.
-->

```bash
<command that finds violations>
```
