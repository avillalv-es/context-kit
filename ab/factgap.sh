#!/bin/sh
# Which facts does arm A never put in front of the agent for a given task,
# that arm B always does? This is the risk side of the tiered layout, and it
# is measurable rather than a matter of opinion.
set -u
AB="$(cd "$(dirname "$0")" && pwd)"
SIZE="${1:-3}"
OUT="$AB/results/factgap.tsv"
mkdir -p "$AB/results"
printf 'task\tfacts_armB\tfacts_armA\tgap\tgap_pct\n' > "$OUT"

gap_for() {
  TASK="$1"; TOUCHED="$2"
  D="$AB/build/size$SIZE-arma"
  # arm B always loads everything
  cat "$AB/build/size$SIZE-armb/CLAUDE.md" | grep -E '^- ' | sort -u > "$AB/build/.fb.txt"
  # arm A loads CLAUDE.md plus the rules whose globs match
  cat "$D/CLAUDE.md" | grep -E '^- ' | sort -u > "$AB/build/.fa.txt"
  DETAIL="$(awk -f "$AB/measure-static.awk" -v arm=a -v dest="$D" -v touched="$TOUCHED" </dev/null | cut -f5)"
  for part in $DETAIL; do
    NM="${part%%:*}"
    [ "$NM" = "CLAUDE.md" ] && continue
    [ -f "$D/.claude/rules/$NM" ] && grep -E '^- ' "$D/.claude/rules/$NM" >> "$AB/build/.fa.txt"
  done
  sort -u "$AB/build/.fa.txt" -o "$AB/build/.fa.txt"
  NB=$(wc -l < "$AB/build/.fb.txt" | tr -d ' ')
  NA=$(wc -l < "$AB/build/.fa.txt" | tr -d ' ')
  G=$(comm -23 "$AB/build/.fb.txt" "$AB/build/.fa.txt" | wc -l | tr -d ' ')
  P=$(awk -v g="$G" -v b="$NB" 'BEGIN{printf "%.0f", b?100*g/b:0}')
  printf '%s\t%s\t%s\t%s\t%s\n' "$TASK" "$NB" "$NA" "$G" "$P" >> "$OUT"
  printf '  %-12s armB %3s facts | armA %3s | never shown %3s (%s%%)\n' "$TASK" "$NB" "$NA" "$G" "$P"
}

gap_for T1-api      "src/api/readings.ts,src/domain/reading.ts"
gap_for T2-billing  "src/domain/billing.ts"
gap_for T3-db       "src/db/migrations/003_x.sql,src/db/readingsRepo.ts"
gap_for T4-worker   "src/workers/ingest.ts,src/lib/config.ts"
printf '\nwrote %s\n' "$OUT"
