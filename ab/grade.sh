#!/bin/sh
# Correctness gate. Each task has load-bearing project knowledge; a run that
# produces working code while violating it is scored WRONG, because that is
# the failure the conventions exist to prevent.
set -u
AB="$(cd "$(dirname "$0")" && pwd)"
PRISTINE="$AB/build/size3-armb"
OUT="$AB/results/grades.tsv"
mkdir -p "$AB/results"
printf 'task\tarm\trep\tverdict\treason\n' > "$OUT"

grade_t1() { # averageKwh must be kWh via toKwh, not raw Wh
  # The check must bind to the NEW FIELD, not to the file: readings.ts already
  # calls toKwh for totalKwh, so "toKwh appears somewhere" passes a solution
  # that returns the new field in raw Wh. That false PASS is the exact bug
  # this task exists to detect.
  D="$1"; F="$D/src/api/readings.ts"
  grep -q 'averageKwh' "$F" 2>/dev/null || { echo "FAIL|field not added"; return; }
  EXPR="$(grep -hoE '(const[[:space:]]+averageKwh[^;]*|averageKwh:[^,}]*)' "$F" 2>/dev/null | tr '\n' ' ')"
  case "$EXPR" in
    *toKwh*) echo "PASS|averageKwh converted with toKwh" ;;
    *)
      # allow the indirection `const x = toKwh(...); ... averageKwh: x`
      VAR="$(printf '%s' "$EXPR" | sed -n 's/.*averageKwh:[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' | head -1)"
      if [ -n "$VAR" ] && grep -qE "(const|let)[[:space:]]+$VAR[^;]*toKwh" "$F" 2>/dev/null; then
        echo "PASS|averageKwh converted with toKwh via $VAR"
      else
        echo "FAIL|averageKwh returns raw Wh"
      fi ;;
  esac
}

grade_t2() { # tariff precedence capacity > timeOfUse > fixed
  D="$1"
  if grep -rqE 'capacity' "$D/src/domain/billing.ts" "$D/src/domain/tariff.ts" 2>/dev/null &&
     grep -rqE 'timeOfUse' "$D/src/domain/billing.ts" "$D/src/domain/tariff.ts" 2>/dev/null; then
    if grep -rq 'active\[0\]' "$D/src/domain/billing.ts" 2>/dev/null; then
      echo "FAIL|still takes active[0]"
    else
      echo "PASS|precedence implemented"
    fi
  else
    echo "FAIL|no precedence ordering found"
  fi
}

grade_t3() { # new numbered migration, CONCURRENTLY, existing migrations untouched
  D="$1"
  NEW="$(ls "$D/src/db/migrations/" 2>/dev/null | grep -vE '^(001_init|002_tariffs)\.sql$' | head -1)"
  [ -n "$NEW" ] || { echo "FAIL|no new migration file"; return; }
  case "$NEW" in 00[3-9]_*.sql|0[1-9][0-9]_*.sql) : ;; *) echo "FAIL|migration not numbered NNN_name.sql: $NEW"; return ;; esac
  for M in 001_init.sql 002_tariffs.sql; do
    if ! cmp -s "$D/src/db/migrations/$M" "$PRISTINE/src/db/migrations/$M"; then
      echo "FAIL|edited an applied migration ($M)"; return
    fi
  done
  if grep -qi 'CONCURRENTLY' "$D/src/db/migrations/$NEW"; then
    echo "PASS|$NEW, CONCURRENTLY, applied migrations untouched"
  else
    echo "FAIL|$NEW lacks CREATE INDEX CONCURRENTLY"
  fi
}

grade_t4() { # guard exists AND the limit comes from config, not a literal
  D="$1"; F="$D/src/workers/ingest.ts"; C="$D/src/lib/config.ts"
  [ -f "$F" ] || { echo "FAIL|no ingest.ts"; return; }
  grep -qE '[Bb]yte' "$F" 2>/dev/null || { echo "FAIL|no byte-size guard"; return; }
  # A 2MB literal in the worker is the failure the convention names, whatever
  # else the file does. Underscores are stripped first so 2_097_152, 2097152
  # and 2_000_000 are all caught. ingest.ts already reads cfg.ingestBatchSize
  # for an unrelated purpose, so "the file mentions cfg." proves nothing.
  if tr -d '_' < "$F" 2>/dev/null | grep -qE '2000000|2097152|2 ?\* ?1024 ?\* ?1024'; then
    echo "FAIL|byte limit hard-coded in the worker, convention says config"; return
  fi
  # Name-agnostic, but bound to a DECLARED key: an interface member or object
  # property, anchored at line start so prose in a comment cannot supply it.
  # The pristine config.ts carries no *Bytes member, so any found is this
  # task's. Pinning an expected name would fail correct solutions that chose
  # a different one.
  KEY="$(grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[Bb]ytes[A-Za-z0-9_]*[[:space:]]*:' "$C" 2>/dev/null \
         | head -1 | tr -d ' \t:')"
  [ -n "$KEY" ] || { echo "FAIL|no byte limit declared in config"; return; }
  if grep -q "$KEY" "$F" 2>/dev/null; then
    echo "PASS|guard present, limit from config.$KEY"
  else
    echo "FAIL|config declares $KEY but the worker never reads it"
  fi
}

# RUNS is overridable so the grader can be validated against known-good and
# known-bad solutions rather than trusted.
RUNS="${RUNS:-$AB/runs}"
ARMS="${ARMS:-a b}"
REPS="${REPS:-1 2 3}"
for T in t1 t2 t3 t4; do
  for A in $ARMS; do
    for R in $REPS; do
      D="$RUNS/$T-$A-r$R"
      [ -d "$D" ] || continue
      case "$T" in
        t1) G="$(grade_t1 "$D")" ;;
        t2) G="$(grade_t2 "$D")" ;;
        t3) G="$(grade_t3 "$D")" ;;
        t4) G="$(grade_t4 "$D")" ;;
      esac
      V="${G%%|*}"; RS="${G#*|}"
      printf '%s\t%s\t%s\t%s\t%s\n' "$T" "$A" "$R" "$V" "$RS" >> "$OUT"
    done
  done
done
awk -F'\t' 'NR>1{printf "  %-3s arm%-2s r%s  %-4s  %s\n",$1,$2,$3,$4,$5}' "$OUT"
printf '\n'
awk -F'\t' 'NR>1{n[$2]++; if($4=="PASS") p[$2]++} END{for(a in n) printf "arm %s: %d/%d correct\n", a, p[a]+0, n[a]}' "$OUT"
