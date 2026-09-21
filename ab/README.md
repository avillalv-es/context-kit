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

## Against a real repository

Everything above measures `meterflow`, which was written for the test. Its
knowledge sorts unusually cleanly into areas, and that is exactly the
condition the tiered layout is best at — so the numbers are the friendly end
of the range, and the writeup says so.

`measure-repo.sh` points the same deterministic measurement at a real repo:

```sh
sh measure-repo.sh <baseline-dir>                  # what the repo costs today
sh measure-repo.sh <baseline-dir> <tiered-dir>     # both arms
```

Two things differ from the meterflow run, and both make the result harder to
flatter:

**Tasks come from git history, not from me.** On meterflow I chose the four
tasks, which is a degree of freedom a real repo does not need. Here each of
the last N commits contributes its changed-file set as one task. Merges,
bulk commits above a fixed threshold, and the root commit drop out — the
rule is set before the run, not after seeing which way it moves the answer.

**Freeze the sample before building the layout.** `repo-sample.tsv` is
written first and is the input to both arms. A tiered layout generated while
looking at the commits it will be scored on can be routed to flatter itself,
so the order is: draw the sample, commit it, then generate the layout from
the repo's existing `CLAUDE.md` alone.

The headline is not the token reduction. It is **routing misses**: the share
of commits where no rule's `paths:` glob matched anything the commit touched.
Those commits still look cheap, because the router is small — but the agent
was handed no area knowledge at all. On meterflow that number is 0% by
construction. On a real repo it is the rate at which the layout quietly
withholds, and it is the number worth acting on.

`repo-sample.tsv` carries commit SHAs and file paths, so it is gitignored;
`repo-static.tsv` is aggregates only and is the half that can be shared.

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
