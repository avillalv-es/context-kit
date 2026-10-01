<!--
  Tier-1 template. Copy to <repo>/CLAUDE.md and rename.

  Named CLAUDE.template.md on purpose: a file literally named CLAUDE.md inside
  this repo would be picked up as real project context while you are editing
  the templates.

  Rules for filling this in:
    - Omit any section you have no real content for. An empty heading is worse
      than no heading; it invites someone to fill it with filler.
    - Every command must have been run. Do not transcribe from a README.
    - Every pointer states its READING CONDITION, not just a path.
    - No directory trees, dependency lists, or architecture summaries.
    - Target under 100 lines for a first version. Hard cap at 200.
-->

# <Project name> — <one line on what it is>

<!--
  Two or three sentences maximum. What this is, who it is for, and the single
  most important thing about its current state (what is built, what is not).
  Not a feature list.
-->

<!--
  OPTIONAL but high value. If this project has decisions that read as bugs to
  someone who does not know the history, list them here and nowhere else.
  This is usually the highest-leverage content in the whole file.
-->

## Things that read as bugs but are not

- **<The surprising behavior>** — <why it is deliberate, and what would break
  if someone "fixed" it>.

## Commands

<!-- Verified against the actual manifest. Every one of these has been run. -->

```bash
<install>
<build>
<test>          # <result, with a "re-measure before quoting" note if you cite a number>
<lint>
<typecheck>
<run>
```

<!-- Non-default ports, hosts, or env vars, and WHY they differ. -->

## Conventions

<!--
  Only what differs from a sensible guess or from the tool's default. If it
  matches the default, leave it out. Point at the full set rather than
  inlining it.
-->

Only what differs from a sensible guess. Full set: `docs/conventions.md`.

- <Convention, stated as a rule, with the reason it is not the obvious choice.>

## Pitfalls

<!--
  Highest-value section. Things with a non-obvious failure mode: the correct
  error, the read-only directory, the thing that must not be "tidied".
-->

- **<The trap>** — <what happens, and what to do instead>.

## Where knowledge lives

<!--
  The router. Each line states the TRIGGER for reading, not just the location.
  "X is in Y" is inert. "Read Y before doing X" is not.
-->

- Before <doing X>, read `docs/<file>.md`.
- Path-scoped rules in `.claude/rules/` load themselves when you touch the
  files they cover. Topic index for everything else: `knowledge/INDEX.md`.
- Findings from a long analysis run go in `findings/`, appended to a file, so
  they survive compaction.

<!--
  No "Context layout" or "Lean execution" section here, on purpose: both are
  plugin-owned. Their text lives in templates/sections/, and /context-init
  stamps them at the end of CLAUDE.md between context-kit markers and keeps
  them current. Without the plugin's command, this does the same:
    sh scripts/claude-sections.sh stamp CLAUDE.md
-->

