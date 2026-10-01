#!/bin/sh
# findings - the working log, and the lessons it adds up to.
#
# Usage:
#   findings.sh record --file NAME --question Q --finding F --outcome OUT \
#                      [--method M] [--sources "a, b"] [--correction C] \
#                      [--confidence confirmed|inferred|unverified]
#   findings.sh reflect [--if-stale | --check] [--out PATH] [--half-life N] [--min-corroboration N]
#   findings.sh help
#
# `record` appends one entry in the shape findings/README.md prescribes, with
# the date filled in absolutely and the outcome in the form `reflect` can
# read. `reflect` reads every entry and writes findings/LESSONS.md. The entry
# files are findings/*.md except LESSONS.md (generated) and README.md (the
# convention, not a log).
#
# `reflect --check` writes nothing and prints nothing: it exits 0 when
# LESSONS.md is current or there is nothing to reflect on, and 3 when
# `--if-stale` would rewrite it. context-sync.sh uses it for its per-session
# staleness line, so the rule lives here and only here.
#
# Nothing here calls a model and nothing here overwrites an entry. A finding
# that proves wrong gets a correction appended after it; the disagreement
# between two runs is itself information.

set -u

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SELF_DIR="."
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/.." 2>/dev/null && pwd)}"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

CMD="${1:-help}"
[ $# -gt 0 ] && shift

FILE=""; QUESTION=""; FINDING=""; METHOD=""; OUTCOME=""
CORRECTION=""; SOURCES=""; CONFIDENCE=""; OUTPATH=""
IF_STALE=0; CHECK=0; HALFLIFE=30; MINCORR=2; DIR=""

die() { printf 'findings: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --file)        FILE="${2:-}"; shift 2 ;;
    --question)    QUESTION="${2:-}"; shift 2 ;;
    --finding)     FINDING="${2:-}"; shift 2 ;;
    --method)      METHOD="${2:-}"; shift 2 ;;
    --outcome)     OUTCOME="${2:-}"; shift 2 ;;
    --correction)  CORRECTION="${2:-}"; shift 2 ;;
    --sources)     SOURCES="${2:-}"; shift 2 ;;
    --confidence)  CONFIDENCE="${2:-}"; shift 2 ;;
    --out)         OUTPATH="${2:-}"; shift 2 ;;
    --dir)         DIR="${2:-}"; shift 2 ;;
    --half-life)   HALFLIFE="${2:-}"; shift 2 ;;
    --min-corroboration) MINCORR="${2:-}"; shift 2 ;;
    --if-stale)    IF_STALE=1; shift ;;
    --check)       CHECK=1; shift ;;
    --root)        ROOT="${2:-}"; shift 2 ;;
    -h|--help)     CMD=help; shift ;;
    *) shift ;;
  esac
done

ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || die "no such directory: $ROOT"
if [ -z "$DIR" ]; then
  if [ -d "$ROOT/findings" ]; then DIR="$ROOT/findings"
  elif [ -d "$ROOT/.claude/findings" ]; then DIR="$ROOT/.claude/findings"
  else DIR="$ROOT/findings"
  fi
fi
[ -n "$OUTPATH" ] || OUTPATH="$DIR/LESSONS.md"

do_record() {
  [ -n "$QUESTION" ] || die "record needs --question (what you were trying to settle)"
  [ -n "$FINDING" ]  || die "record needs --finding (the conclusion)"
  case "$OUTCOME" in
    useful|dead_end|corrected) : ;;
    "") die "record needs --outcome: useful, dead_end or corrected" ;;
    *) die "unknown outcome '$OUTCOME' - use useful, dead_end or corrected" ;;
  esac
  if [ "$OUTCOME" = "corrected" ] && [ -z "$CORRECTION" ]; then
    die "outcome 'corrected' needs --correction (what turned out to be true)"
  fi

  if [ -z "$FILE" ]; then
    FILE="$(printf '%s' "$QUESTION" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' \
            | sed 's/^-*//;s/-*$//' | cut -c1-50)"
    [ -n "$FILE" ] || FILE="investigation"
  fi
  case "$FILE" in *.md) : ;; *) FILE="$FILE.md" ;; esac
  case "$FILE" in
    */*|..*) die "--file is a name inside $DIR, not a path" ;;
  esac

  mkdir -p "$DIR" 2>/dev/null || die "cannot create $DIR"
  TARGET="$DIR/$FILE"
  DATE="$(date -u '+%Y-%m-%d' 2>/dev/null)"
  [ -n "$DATE" ] || die "cannot read the date"

  # One file per investigation, appended to, never overwritten. A dated
  # heading is what makes the entry parseable and what makes it readable in
  # three months; a relative date is neither.
  if [ ! -f "$TARGET" ]; then
    TITLE="$(printf '%s' "$FILE" | sed 's/\.md$//' | tr '-' ' ')"
    printf '# %s\n\nWorking log. Appended to, never overwritten.\n' "$TITLE" > "$TARGET"
  fi

  # `[ -n "$X" ] && printf ...` as the last line of the group makes the whole
  # group exit 1 whenever that optional field is empty, which reads as a
  # failed write on an append that in fact succeeded.
  {
    printf '\n## %s — %s\n\n' "$DATE" "$(printf '%s' "$QUESTION" | cut -c1-70)"
    printf '**Question:** %s\n\n' "$QUESTION"
    if [ -n "$METHOD" ];     then printf '**Method:** %s\n\n' "$METHOD"; fi
    printf '**Finding:** %s\n\n' "$FINDING"
    printf '**Outcome:** %s\n\n' "$OUTCOME"
    if [ -n "$CONFIDENCE" ]; then printf '**Confidence:** %s\n\n' "$CONFIDENCE"; fi
    if [ -n "$SOURCES" ];    then printf '**Sources:** %s\n\n' "$SOURCES"; fi
    if [ -n "$CORRECTION" ]; then printf '**Correction:** %s\n\n' "$CORRECTION"; fi
  } >> "$TARGET" || die "cannot append to $TARGET"

  printf 'appended to %s\n' "${TARGET#"$ROOT"/}"
}

# True when LESSONS.md should be (re)written: it is missing, or an entry file
# is newer than it. $SRC is the entry list do_reflect built.
lessons_stale() {
  [ -f "$OUTPATH" ] || return 0
  for f in $SRC; do
    [ "$f" -nt "$OUTPATH" ] && return 0
  done
  return 1
}

do_reflect() {
  # --check is a question, not a task: no directory or no entries means there
  # is nothing to be stale, so it answers 0 rather than complaining.
  if [ "$CHECK" -eq 1 ] && [ ! -d "$DIR" ]; then exit 0; fi
  [ -d "$DIR" ] || { printf 'findings: no %s yet - nothing to reflect on\n' "${DIR#"$ROOT"/}" >&2; exit 2; }
  SRC=""
  for f in "$DIR"/*.md; do
    [ -f "$f" ] || continue
    # LESSONS.md is this command's own output; README.md is the convention
    # copied in by /context-init, not a log of findings.
    case "$f" in */LESSONS.md|*/README.md) continue ;; esac
    SRC="$SRC $f"
  done
  if [ "$CHECK" -eq 1 ]; then
    [ -n "$SRC" ] || exit 0
    if lessons_stale; then exit 3; fi
    exit 0
  fi
  [ -n "$SRC" ] || { printf 'findings: no entries in %s\n' "${DIR#"$ROOT"/}" >&2; exit 2; }

  # --if-stale makes this cheap enough to run at the start of every session:
  # when nothing has been appended since the last run, recomputing produces
  # the same bytes, so do not.
  if [ "$IF_STALE" -eq 1 ] && ! lessons_stale; then
    printf 'findings: %s is current\n' "${OUTPATH#"$ROOT"/}"
    return 0
  fi

  TODAY="$(date -u '+%Y-%m-%d' 2>/dev/null)"
  TMP="$OUTPATH.tmp.$$"
  # shellcheck disable=SC2086
  awk -f "$PLUGIN_ROOT/scripts/findings.awk" \
      -v today="$TODAY" -v halflife="$HALFLIFE" -v mincorr="$MINCORR" \
      $SRC > "$TMP" || { rm -f "$TMP"; die "reflect failed"; }
  [ -s "$TMP" ] || { rm -f "$TMP"; die "reflect produced nothing"; }
  mv "$TMP" "$OUTPATH"
  printf 'wrote %s\n' "${OUTPATH#"$ROOT"/}"
  sed -n '/^## Summary/,/^$/p' "$OUTPATH" | sed -n '3p'
}

case "$CMD" in
  record)  do_record ;;
  reflect) do_reflect ;;
  help|*)
    cat <<'HELP'
findings - the working log, and the lessons it adds up to

  record   append one entry to findings/<name>.md
           --question Q --finding F --outcome useful|dead_end|corrected
           --file NAME --method M --sources "a, b" --correction C
           --confidence confirmed|inferred|unverified

  reflect  read every entry, write findings/LESSONS.md
           --if-stale            no-op when LESSONS.md is already current
           --check               write nothing; exit 3 when it is stale, else 0
           --half-life N         days after which a signal counts half (30)
           --min-corroboration N useful entries before "preferred" (2)
           --out PATH            write somewhere else

Deterministic: no model, stable ordering, same bytes for the same input on
the same day. An entry is appended, never edited; a finding that proves
wrong gets a correction appended after it.
HELP
    ;;
esac
