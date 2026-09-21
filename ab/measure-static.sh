#!/bin/sh
# Layer 1 of the A/B: exactly how much project context each layout forces a
# session to load, per task. Deterministic, re-runnable, checkable by hand.
set -u
AB="$(cd "$(dirname "$0")" && pwd)"
OUT="$AB/results/static.tsv"
mkdir -p "$AB/results"

# task<TAB>touched files
TASKS="
t1-api-field	src/api/readings.ts,src/domain/reading.ts
t2-billing-fix	src/domain/billing.ts
t3-db-index	src/db/migrations/003_readings_bucket_idx.sql,src/db/readingsRepo.ts
t4-worker-guard	src/workers/ingest.ts,src/lib/config.ts
"

printf 'size\ttask\tarm\tbytes\test_tokens\tfiles\tdetail\n' > "$OUT"
for SIZE in 1 2 3; do
  for ARM in a b; do
    D="$AB/build/size$SIZE-arm$ARM"
    sh "$AB/compose.sh" "$ARM" "$SIZE" "$D" >/dev/null
  done
  printf '%s' "$TASKS" | while IFS="$(printf '\t')" read -r TASK TOUCHED; do
    [ -n "$TASK" ] || continue
    for ARM in a b; do
      D="$AB/build/size$SIZE-arm$ARM"
      R="$(awk -f "$AB/measure-static.awk" -v arm="$ARM" -v dest="$D" -v touched="$TOUCHED" </dev/null)"
      printf '%s\t%s\t%s\n' "$SIZE" "$TASK" "$R" >> "$OUT"
    done
  done
done
awk -F"\t" '{printf "%-5s %-15s %-4s %8s %8s %6s\n",$1,$2,$3,$4,$5,$6}' "$OUT"
printf '\nwrote %s\n' "$OUT"
