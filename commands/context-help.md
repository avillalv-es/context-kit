---
description: Quick reference for context-kit commands, levels and layout
---

Print this reference verbatim, adjusted only where the current repo differs.
Add no commentary.

```
context-kit

  Layout
    /context-init            set up or rebalance the three-tier layout
    /context-init bootstrap  scaffold + stamp the marker only, no survey
    /context                 (built-in) the real context-window number

  Skills
    /skill-capture           turn a repeatable procedure into a project skill
    /lean-review [--repo]    what can be deleted; diff by default
    /shortcut-ledger         every deliberate shortcut marked in this repo

  Lean execution
    /lean lite               build it, then name the leaner option in one line
    /lean full               the ladder enforced (default)
    /lean ultra              deletion before addition
    /lean off                no ruleset injected

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
    CONTEXT_KIT_NO_SIGNALS=1  disable repeat detection only
    CONTEXT_KIT_LEVEL=<lvl>   override the lean level for one session
```
