---
description: Quick reference for context-kit commands, levels and layout
---

Print this reference verbatim, adjusted only where the current repo differs.
Add no commentary.

```
context-kit

  Layout
    /context-init            set up the three-tier layout, or refresh it
    /context-init cleanup    audit and rebalance; stops at a table first
    /context-init bootstrap  scaffold + stamp the managed sections, no survey
    /context-init off <s>    turn a managed CLAUDE.md section off (or: on <s>)
                             sections: context-layout, lean-execution,
                             model-routing, context-sync, pr-train
                             refreshed on re-run; edits inside the markers
                             are overwritten
    /context-sync            route PROGRESS.md, docs/ and notes into the tiers
    /context-sync off|on     turn the session-start sync off or on
    /context-sync sources add <glob>|list
                             extra markdown to treat as sources
    /context-graph           draw the layout; also `serve`, `vault`, `open`
    /context-graph --code    add the module import layer
    /context                 (built-in) the real context-window number

  Skills
    /skill-capture           turn a repeatable procedure into a project skill
    /lean-review [--repo]    what can be deleted; diff by default
    /shortcut-ledger         every deliberate shortcut marked in this repo

  Impact
    /blast-radius --diff     what breaks, given everything you just changed
    /blast-radius <symbol>   what depends on a function, class or constant
    /blast-radius --file P   what depends on a file

  Findings
    /finding                 record what you just settled, or a dead end
    /finding reflect         roll every entry into findings/LESSONS.md

  PR train
    /pr-train                split the agreed plan into PRs, or resume the
                             active train in .claude/handoff/
    /pr-train status         show the train's task list
    /pr-train off|on         turn the CLAUDE.md section off or on

  Lean execution
    /lean lite               build it, then name the leaner option in one line
    /lean full               the ladder enforced (default)
    /lean ultra              deletion before addition
    /lean off                no ruleset injected
    /model-routing           show whether model routing is on; also on, off

  Tiers
    1  CLAUDE.md                     every session, always. Routing + the rare
                                     fact that is wrong-answer-generating
                                     everywhere. Capped at 200 lines.
    2  .claude/rules/*.md            only when a file matching `paths:` is
                                     touched.
    3  knowledge/*.md                only when looked up.
       .claude/skills/*/SKILL.md     only when the description matches.
    -  delete                        directory trees, dependency lists, file
                                     inventories, architecture summaries.

  Environment
    CONTEXT_KIT_OFF=1         disable every context-kit hook
    CONTEXT_KIT_NO_SIGNALS=1  disable repeat detection and the activity ledger
    CONTEXT_KIT_NO_ACTIVITY=1 disable the activity ledger only
    CONTEXT_KIT_LEVEL=<lvl>   override the lean level for one session
```
