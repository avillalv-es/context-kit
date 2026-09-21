# A/B: three-tier layout vs one monolithic CLAUDE.md

Does context-kit's layout actually beat the thing it claims to beat?

Both arms hold **exactly the same facts**. Only the shape differs.

- **Arm B** — one flat `CLAUDE.md`.
- **Arm A** — a tier-1 router, `.claude/rules/*.md` scoped by `paths:` globs, and
  `knowledge/` for reference material.

Both are generated from `blocks/`, so parity is structural rather than asserted,
and `verify-parity.sh` proves it at every size.

## The subject

`src/meterflow/` — a ~30-file TypeScript energy-metering service. Small files,
extensive structure. It carries facts that are **wrong-answer-generating**: the
canonical storage unit is Wh and the API returns kWh; tariff precedence is
`capacity > timeOfUse > fixed`; applied migrations are never edited. A run that
misses one of those produces a *wrong* result, not merely a slower one.

`src/domain/billing.ts` ships with a real bug — it takes `active[0]`, which
ADR 002 explicitly calls wrong.

## Running it

```sh
sh measure-static.sh     # layer 1: exact context cost per task, per arm, per size
sh verify-parity.sh      # asserts both arms carry identical facts
sh factgap.sh 3          # how many facts arm A never shows the agent
sh grade.sh              # correctness of each completed run
python3 collect-tokens.py  # layer 2: per-run token telemetry from the transcripts
python3 report.py          # rebuild the SVG charts
sh render.sh               # screenshot them to PNG
```

`collect-tokens.py` reads the subagent transcripts rather than context-kit's
own activity ledger. The ledger only records the file-reading tool, and these
agents read through `cat` and `grep` far more often, so it undercounts badly.

`results/` holds the raw TSVs every chart is drawn from.

## Layers

**Layer 1, deterministic.** Exactly how many bytes of project context each
layout forces a session to load, per task. No model involved; re-runnable;
checkable by hand. This is the primary result.

**Layer 2, empirical.** Four tasks x two arms x three repetitions = 24 subagent
runs, one workflow per arm so each arm's token total is clean. Low statistical
power by construction — see the summary for what that does and does not permit.

## The honest caveats

- `knowledge/` counts as zero in layer 1, because tier 3 is reached by lookup.
  That IS the claim under test, not a neutral accounting choice.
- The hook-injected ruleset fires for **both** arms identically, so it is a
  constant and cannot explain any gap.
- N=3 per cell, one project, one model, one session. An existence check, not a
  benchmark.
