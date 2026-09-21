#!/bin/sh
# Assert the two arms hold the SAME facts, differing only in layout.
#
# Both are generated from ab/blocks/, so this should pass by construction.
# It exists because "same knowledge, different shape" is the entire premise of
# the experiment, and a premise nobody checked is a premise that is wrong.
set -u
AB="$(cd "$(dirname "$0")" && pwd)"
FAIL=0

for SIZE in 1 2 3; do
  CANON="$AB/build/.canon-$SIZE.txt"
  : > "$CANON"
  for f in "$AB"/blocks/*.block; do
    T="$(head -1 "$f" | cut -d'|' -f2)"
    [ "$T" -le "$SIZE" ] || continue
    tail -n +2 "$f" | grep -v '^[[:space:]]*$' >> "$CANON"
  done
  sort -u "$CANON" -o "$CANON"

  for ARM in a b; do
    D="$AB/build/size$SIZE-arm$ARM"
    [ -d "$D" ] || { printf 'FAIL  size%s arm%s not built\n' "$SIZE" "$ARM"; FAIL=1; continue; }
    ALL="$AB/build/.all-$SIZE-$ARM.txt"
    find "$D" -name '*.md' \( -path '*/knowledge/*' -o -path '*/.claude/rules/*' -o -name 'CLAUDE.md' \) \
      | xargs cat 2>/dev/null | grep -v '^[[:space:]]*$' | sort -u > "$ALL"
    MISSING="$(comm -23 "$CANON" "$ALL" | wc -l | tr -d ' ')"
    if [ "$MISSING" -eq 0 ]; then
      printf 'ok    size%s arm%s carries every fact (%s lines)\n' "$SIZE" "$ARM" "$(wc -l < "$CANON" | tr -d ' ')"
    else
      printf 'FAIL  size%s arm%s is missing %s fact lines:\n' "$SIZE" "$ARM" "$MISSING"
      comm -23 "$CANON" "$ALL" | head -5 | sed 's/^/        /'
      FAIL=1
    fi
  done
done

printf '\n'
[ "$FAIL" -eq 0 ] && printf 'Both arms hold identical knowledge at every size.\n' || printf 'Parity broken - the experiment would be invalid.\n'
exit "$FAIL"
