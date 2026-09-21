#!/bin/sh
# Compose one arm of the A/B from the shared knowledge blocks.
#
#   compose.sh <arm: a|b> <size: 1|2|3> <destdir>
#
# Both arms are generated from ab/blocks/, so they hold the same facts by
# construction rather than by assertion. verify-parity.sh proves it after.
set -u
ARM="${1:?arm}"; SIZE="${2:?size}"; DEST="${3:?dest}"
AB="$(cd "$(dirname "$0")" && pwd)"
BLOCKS="$AB/blocks"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$AB/src/meterflow/." "$DEST/"

# header of a block file is "PATHS|TIER"
bpaths() { head -1 "$1" | cut -d'|' -f1; }
btier()  { head -1 "$1" | cut -d'|' -f2; }
bbody()  { tail -n +2 "$1"; }

if [ "$ARM" = "b" ]; then
  # ---- baseline: one flat CLAUDE.md ------------------------------------
  {
    printf '# meterflow\n\n'
    printf 'Project conventions. Read this before changing anything.\n\n'
    for f in "$BLOCKS"/*.block; do
      [ "$(btier "$f")" -le "$SIZE" ] || continue
      bbody "$f"
      printf '\n'
    done
  } > "$DEST/CLAUDE.md"
else
  # ---- context-kit: tier-1 router + conditional rules + tier-3 knowledge
  mkdir -p "$DEST/.claude/rules" "$DEST/knowledge"
  CORE="$BLOCKS/00-core.block"
  {
    printf '# meterflow\n\n'
    printf 'Project conventions. Read this before changing anything.\n\n'
    bbody "$CORE"
    printf '\n## Context layout\n\n'
    printf 'Knowledge that only applies to one area lives with that area, and\n'
    printf 'loads only when a matching file is touched.\n\n'
    printf '| Area | Read when |\n|---|---|\n'
    for f in "$BLOCKS"/*.block; do
      [ "$f" = "$CORE" ] && continue
      [ "$(btier "$f")" -le "$SIZE" ] || continue
      P="$(bpaths "$f")"
      NAME="$(basename "$f" .block)"
      TITLE="$(sed -n '2p' "$f" | sed 's/^# //')"
      if [ "$P" = "*" ]; then
        printf '| `knowledge/%s.md` | %s - look up when relevant |\n' "$NAME" "$TITLE"
      else
        printf '| `.claude/rules/%s.md` | touching `%s` |\n' "$NAME" "$P"
      fi
    done
    printf '\nReference material is in `knowledge/`; it costs nothing until read.\n'
  } > "$DEST/CLAUDE.md"

  for f in "$BLOCKS"/*.block; do
    [ "$f" = "$CORE" ] && continue
    [ "$(btier "$f")" -le "$SIZE" ] || continue
    P="$(bpaths "$f")"
    NAME="$(basename "$f" .block)"
    TITLE="$(sed -n '2p' "$f" | sed 's/^# //')"
    if [ "$P" = "*" ]; then
      bbody "$f" > "$DEST/knowledge/$NAME.md"
    else
      {
        printf -- '---\n'
        printf 'description: Use when touching %s. %s.\n' "$P" "$TITLE"
        printf 'paths:\n  - "%s"\n' "$P"
        printf -- '---\n\n'
        bbody "$f"
      } > "$DEST/.claude/rules/$NAME.md"
    fi
  done
  # tier-3 index so the knowledge is reachable, per the three-tier model
  {
    printf '# Knowledge index\n\n'
    for k in "$DEST"/knowledge/*.md; do
      [ -f "$k" ] || continue
      [ "$(basename "$k")" = "INDEX.md" ] && continue
      printf -- '- [%s](%s) - %s\n' "$(basename "$k" .md)" "$(basename "$k")" \
        "$(sed -n '1p' "$k" | sed 's/^# //')"
    done
  } > "$DEST/knowledge/INDEX.md"
fi
