#!/bin/sh
# The deterministic context-cost measurement, pointed at a real repository
# instead of the synthetic meterflow.
#
# Usage: sh measure-repo.sh <baseline-dir> [tiered-dir] [options]
#
#   baseline-dir  a checkout carrying the monolithic CLAUDE.md
#   tiered-dir    a checkout of the SAME repo carrying the tier-1 router and
#                 .claude/rules/*.md; omit it to measure only what the repo
#                 costs today
#
#   --commits N   how many recent commits to sample (default 50)
#   --bulk N      skip a commit touching more than N files (default 40)
#   --paths       include directory names in the output; off by default so a
#                 result can leave the team without carrying the repo's
#                 structure with it
#   --out DIR     where the TSVs go (default: this script's results/)
#
# Why commits rather than hand-picked tasks: on meterflow the four tasks were
# chosen by the person running the experiment, which is a degree of freedom a
# real repo does not need. A commit's changed-file set is a task somebody
# actually did, and fifty of them give a distribution instead of four points.
#
# Order matters and is not negotiable: draw and freeze the sample BEFORE the
# tiered layout is generated. A layout built while looking at the commits it
# will be scored on can be routed to flatter itself.
set -u
AB="$(cd "$(dirname "$0")" && pwd)"
COMMITS=50
BULK=40
SHOWPATHS=0
OUT="$AB/results"

BASE=""
TIER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --commits) COMMITS="$2"; shift 2 ;;
    --bulk)    BULK="$2"; shift 2 ;;
    --paths)   SHOWPATHS=1; shift ;;
    --out)     OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    -*)        printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    *)         if [ -z "$BASE" ]; then BASE="$1"; else TIER="$1"; fi; shift ;;
  esac
done

[ -n "$BASE" ] || { printf 'usage: sh measure-repo.sh <baseline-dir> [tiered-dir]\n' >&2; exit 2; }
BASE="$(cd "$BASE" 2>/dev/null && pwd)" || { printf 'no such directory\n' >&2; exit 2; }
[ -d "$BASE/.git" ] || { printf '%s is not a git checkout\n' "$BASE" >&2; exit 2; }
[ -f "$BASE/CLAUDE.md" ] || { printf '%s has no CLAUDE.md to measure\n' "$BASE" >&2; exit 2; }
if [ -n "$TIER" ]; then
  TIER="$(cd "$TIER" 2>/dev/null && pwd)" || { printf 'no such tiered directory\n' >&2; exit 2; }
  [ -f "$TIER/CLAUDE.md" ] || { printf '%s has no tier-1 CLAUDE.md\n' "$TIER" >&2; exit 2; }
fi
mkdir -p "$OUT"

SAMPLE="$OUT/repo-sample.tsv"
STATIC="$OUT/repo-static.tsv"

# --- 1. freeze the sample --------------------------------------------------
# Merges carry no authored change set. Bulk commits - a vendor drop, a mass
# reformat - are not tasks either, and the threshold is fixed here rather
# than tuned after seeing which way it moves the answer. A root commit has
# no parent to diff against, so git reports no files and it drops out too,
# which is right: importing a codebase is not a task either.
printf 'idx\tsha\tnfiles\tfiles\n' > "$SAMPLE"
IDX=0
git -C "$BASE" log --no-merges -n "$COMMITS" --pretty=format:%H | while IFS= read -r SHA; do
  FILES="$(git -C "$BASE" show --name-only --pretty=format: "$SHA" 2>/dev/null \
           | sed '/^$/d' | sort -u | tr '\n' ',' | sed 's/,$//')"
  [ -n "$FILES" ] || continue
  N="$(printf '%s' "$FILES" | tr ',' '\n' | wc -l | tr -d ' ')"
  [ "$N" -le "$BULK" ] || continue
  IDX=$((IDX + 1))
  printf '%s\t%s\t%s\t%s\n' "$IDX" "$SHA" "$N" "$FILES" >> "$SAMPLE"
done

NSAMP="$(($(wc -l < "$SAMPLE" | tr -d ' ') - 1))"
[ "$NSAMP" -gt 0 ] || { printf 'no usable commits in the last %s\n' "$COMMITS" >&2; exit 1; }

# --- 2. measure both arms against the frozen sample ------------------------
printf 'idx\tnfiles\tarm\tbytes\test_tokens\tfiles_loaded\tdetail\n' > "$STATIC"
tail -n +2 "$SAMPLE" | while IFS="$(printf '\t')" read -r I SHA N FILES; do
  R="$(awk -f "$AB/measure-static.awk" -v arm=b -v dest="$BASE" -v touched="$FILES" </dev/null)"
  printf '%s\t%s\t%s\n' "$I" "$N" "$R" >> "$STATIC"
  if [ -n "$TIER" ]; then
    R="$(awk -f "$AB/measure-static.awk" -v arm=a -v dest="$TIER" -v touched="$FILES" </dev/null)"
    printf '%s\t%s\t%s\n' "$I" "$N" "$R" >> "$STATIC"
  fi
done

# --- 3. report -------------------------------------------------------------
printf '\nrepo          %s\n' "$(basename "$BASE")"
printf 'commits       %s sampled of the last %s (merges and >%s-file commits skipped)\n' \
  "$NSAMP" "$COMMITS" "$BULK"
printf 'CLAUDE.md     %s lines\n' "$(wc -l < "$BASE/CLAUDE.md" | tr -d ' ')"
if [ -n "$TIER" ]; then
  printf 'tier-1 router %s lines, %s rule files\n' \
    "$(wc -l < "$TIER/CLAUDE.md" | tr -d ' ')" \
    "$(ls "$TIER/.claude/rules/"*.md 2>/dev/null | wc -l | tr -d ' ')"
fi
printf '\n'

awk -F'\t' -v tiered="${TIER:-}" '
  NR > 1 { tok[$1 "|" $3] = $5; loaded[$1 "|" $3] = $6; nf[$1] = $2 }
  END {
    n = 0; sb = 0; sa = 0; nomatch = 0
    for (k in tok) {
      split(k, p, "|")
      if (p[2] != "b") continue
      i = p[1]; n++
      b = tok[i "|b"]; sb += b
      if (tiered == "") continue
      a = tok[i "|a"]
      sa += a
      cut = (b > 0) ? (1 - a / b) * 100 : 0
      cuts[n] = cut
      # files_loaded of 1 means tier-1 and nothing else: no rule glob matched
      # anything this commit touched. The tokens still look good - the router
      # is tiny - but the agent was handed no area knowledge at all, and that
      # is the risk the saving is bought with.
      if (loaded[i "|a"] + 0 <= 1) nomatch++
    }
    if (n == 0) { print "no rows"; exit }
    printf "per-commit context a session must load\n"
    printf "  one CLAUDE.md   %8.0f est tokens, every commit\n", sb / n
    if (tiered == "") {
      printf "\nNo tiered directory given, so this is the cost as the repo stands.\n"
      printf "Generate the layout, then re-run with both directories.\n"
      exit
    }
    # median and the tail, because a mean hides the commits that route badly
    for (i = 1; i <= n; i++)
      for (j = i + 1; j <= n; j++)
        if (cuts[j] < cuts[i]) { t = cuts[i]; cuts[i] = cuts[j]; cuts[j] = t }
    med = (n % 2) ? cuts[int((n + 1) / 2)] : (cuts[n / 2] + cuts[n / 2 + 1]) / 2
    printf "  context-kit     %8.0f est tokens mean\n", sa / n
    printf "\nreduction       median %.0f%%, worst %.0f%%, best %.0f%%\n", med, cuts[1], cuts[n]
    printf "\nrouting misses  %d of %d commits (%.0f%%) matched no rule at all\n", \
      nomatch, n, nomatch * 100 / n
    printf "\nThat second number is the one a synthetic project cannot produce, and\n"
    printf "it is not a token figure. A commit that matches no rule still looks\n"
    printf "cheap, because the router is small - but the agent was handed no area\n"
    printf "knowledge whatsoever. On meterflow this is 0%% by construction. On a\n"
    printf "real repo it is the rate at which the layout quietly withholds.\n"
  }
' "$STATIC"

printf '\nwrote %s\n' "$STATIC"
if [ "$SHOWPATHS" -eq 0 ]; then
  printf 'wrote %s  (holds commit SHAs and file paths - keep it internal)\n' "$SAMPLE"
fi
