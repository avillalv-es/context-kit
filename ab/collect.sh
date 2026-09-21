#!/bin/sh
# Pull per-run file access out of the context-kit activity ledger.
#
# The ledger's actor column is the session id, shared by every subagent, so
# attribution is by PATH: each run has its own directory, which makes every
# recorded read unambiguously one arm's. Matching on the run segment rather
# than a fixed prefix keeps it correct even if CLAUDE_PROJECT_DIR moved
# mid-session and the ledger rotated to a second file.
set -u
AB="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$AB/results"
OUT="$AB/results/runs.tsv"

cat "$HOME/.claude/context-kit/events/"*.tsv 2>/dev/null \
  | awk -F'\t' '
      { if (match($4, /runs\/t[0-9]+-[ab]-r[0-9]+\//)) {
          seg = substr($4, RSTART, RLENGTH)
          gsub(/^runs\/|\/$/, "", seg)
          rest = substr($4, RSTART + RLENGTH)
          split(seg, P, "-")
          key = P[1] "\t" P[2] "\t" substr(P[3], 2)
          tot[key]++
          if ($2 == "read")  rd[key]++
          if ($2 == "write") wr[key]++
          if (rest ~ /^(CLAUDE\.md|\.claude\/rules\/|knowledge\/)/) ctx[key]++
          seen[key] = 1
        } }
      END {
        print "task\tarm\trep\ttouches\treads\twrites\tcontext_reads"
        for (k in seen) printf "%s\t%d\t%d\t%d\t%d\n", k, tot[k], rd[k]+0, wr[k]+0, ctx[k]+0
      }' | (read -r H; printf '%s\n' "$H"; sort) > "$OUT"

printf 'per-run access (from the ledger)\n'
awk -F'\t' 'NR>1{printf "  %-3s arm%-2s r%s  touches %3s  reads %3s  writes %3s  context %2s\n",$1,$2,$3,$4,$5,$6,$7}' "$OUT"
printf '\nper-arm totals\n'
awk -F'\t' 'NR>1{t[$2]+=$4; r[$2]+=$5; w[$2]+=$6; c[$2]+=$7; n[$2]++}
  END{for(a in n) printf "  arm %s: %d runs, %d touches, %d reads, %d writes, %d context reads\n", a, n[a], t[a], r[a], w[a], c[a]}' "$OUT"
printf '\nwrote %s\n' "$OUT"
