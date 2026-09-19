#!/bin/sh
# blast-radius - what breaks if this changes.
#
# Usage:
#   blast-radius.sh <symbol>            trace a function, class or constant
#   blast-radius.sh --file <path>       trace a file
#   blast-radius.sh --diff [--base REF] trace everything changed in the tree
#
#   --depth N     hops to walk back (default 3)
#   --max N       rows per depth (default 40)
#   --cached      reuse the existing import graph instead of rebuilding
#   --root DIR    project root
#
# Walks IMPORTERS. grep finds where a name appears; only the reversed import
# graph answers what depends on the thing you are about to change, and only
# it can follow the chain two and three files out.
#
# It is file-level, so it is a strong starting set and never a complete one.
# Anything wired at runtime - a route table, a DI container, a plugin
# registry, a string-keyed factory - is invisible to it, and the report says
# so rather than letting the silence read as "nothing else is affected".

set -u

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SELF_DIR="."
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/.." 2>/dev/null && pwd)}"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
OUT=""
DEPTH=3
MAX=40
CACHED=0
MODE=""
TARGET=""
BASE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --file)   MODE=file; TARGET="${2:-}"; shift 2 ;;
    --diff)   MODE=diff; shift ;;
    --base)   BASE="${2:-}"; shift 2 ;;
    --depth)  DEPTH="${2:-3}"; shift 2 ;;
    --max)    MAX="${2:-40}"; shift 2 ;;
    --root)   ROOT="${2:-}"; shift 2 ;;
    --out)    OUT="${2:-}"; shift 2 ;;
    --cached) CACHED=1; shift ;;
    -h|--help) MODE=help; shift ;;
    --*) shift ;;
    *) [ -z "$MODE" ] && { MODE=symbol; TARGET="$1"; }; shift ;;
  esac
done

if [ "$MODE" = "help" ] || [ -z "$MODE" ]; then
  cat <<'HELP'
blast-radius - what breaks if this changes

  blast-radius.sh <symbol>             trace a function, class or constant
  blast-radius.sh --file <path>        trace a file
  blast-radius.sh --diff               trace everything changed in the tree
  blast-radius.sh --diff --base main   ...changed against a branch

  --depth N   hops to walk back (default 3)
  --max N     rows shown per depth (default 40)
  --cached    reuse the existing import graph instead of rebuilding

File level: it follows imports, so it sees what depends on what. It cannot
see runtime wiring - route tables, DI containers, plugin registries - and
says so in the report rather than leaving you to assume it looked.
HELP
  exit 0
fi

ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { printf 'blast-radius: no such directory\n' >&2; exit 1; }
[ -n "$OUT" ] || OUT="$ROOT/.claude/context-graph"
cd "$ROOT" || exit 1

if [ "$CACHED" -eq 0 ] || [ ! -f "$OUT/imports.tsv" ]; then
  sh "$PLUGIN_ROOT/scripts/code-graph.sh" --root "$ROOT" --out "$OUT" --quiet || {
    printf 'blast-radius: could not build the import graph\n' >&2; exit 1; }
fi
[ -f "$OUT/imports.tsv" ] || { printf 'blast-radius: no import graph at %s\n' "$OUT" >&2; exit 1; }

TMP="$OUT/.tmp.br.$$"
mkdir -p "$TMP" || exit 1
trap 'rm -rf "$TMP" 2>/dev/null' EXIT INT TERM
: > "$TMP/seeds.txt"
: > "$TMP/hits.txt"
SYMBOL=""
NOTE=""

case "$MODE" in
  file)
    [ -n "$TARGET" ] || { printf 'blast-radius: --file needs a path\n' >&2; exit 1; }
    T="$(printf '%s' "$TARGET" | sed "s|^$ROOT/||;s|^\./||")"
    if [ ! -f "$T" ]; then
      printf 'blast-radius: no such file: %s\n' "$T" >&2
      exit 1
    fi
    printf '%s\n' "$T" > "$TMP/seeds.txt"
    ;;

  diff)
    # The audit and debugging case: you already changed things, and the
    # question is what else you now have to look at.
    if [ -n "$BASE" ]; then
      git diff --name-only "$BASE"...HEAD 2>/dev/null > "$TMP/seeds.txt"
    else
      # Unstaged, staged, AND untracked. A new file is the most common thing
      # an audit adds, and `git diff` alone never mentions it, so leaving it
      # out reports "nothing changed" in the middle of a large change.
      { git diff --name-only 2>/dev/null
        git diff --name-only --staged 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null
      } | sort -u > "$TMP/seeds.txt"
    fi
    # Keep only paths that still exist; a deleted file has no importers to walk.
    : > "$TMP/seeds2.txt"
    while IFS= read -r f; do
      [ -n "$f" ] && [ -f "$f" ] && printf '%s\n' "$f" >> "$TMP/seeds2.txt"
    done < "$TMP/seeds.txt"
    mv "$TMP/seeds2.txt" "$TMP/seeds.txt"
    if [ ! -s "$TMP/seeds.txt" ]; then
      printf 'blast-radius: nothing changed%s - nothing to trace\n' \
        "$([ -n "$BASE" ] && printf ' against %s' "$BASE")"
      exit 0
    fi
    ;;

  symbol)
    SYMBOL="$TARGET"
    [ -n "$SYMBOL" ] || { printf 'blast-radius: give a symbol, a --file or --diff\n' >&2; exit 1; }
    case "$SYMBOL" in
      *[!A-Za-z0-9_.\$-]*) printf 'blast-radius: %s does not look like a symbol\n' "$SYMBOL" >&2; exit 1 ;;
    esac

    if command -v rg >/dev/null 2>&1; then
      GREP_ALL="rg --no-heading --line-number --no-messages --color never"
    else
      GREP_ALL=""
    fi

    # Seed on the DEFINITION, not on every mention. Tracing from every file
    # that says the word makes the walk start everywhere and mean nothing.
    DEFRE="(^|[^A-Za-z0-9_])(function|class|const|let|var|def|type|interface|enum|struct|trait|impl|fn|func|public|private|protected|internal|export|module|object|record)([ \t]+[A-Za-z_][A-Za-z0-9_]*)*[ \t]+${SYMBOL}([ \t]*[({:<=]|[ \t]*\$)"
    ASSIGNRE="(^|[^A-Za-z0-9_])${SYMBOL}[ \t]*[:=][ \t]*(function|async|\(|class|new )"
    if [ -n "$GREP_ALL" ]; then
      $GREP_ALL -e "$DEFRE" -e "$ASSIGNRE" . 2>/dev/null | cut -d: -f1 | sort -u > "$TMP/seeds.txt"
    else
      grep -rIlE -e "$DEFRE" -e "$ASSIGNRE" . 2>/dev/null | sed 's|^\./||' | sort -u > "$TMP/seeds.txt"
    fi
    # `A || B && C` groups as `(A || B) && C`, so an in-place sed that
    # succeeds still ran the fallback's mv and failed on a file that was
    # never written. One form, no chain.
    sed 's|^\./||' "$TMP/seeds.txt" > "$TMP/s2" && mv "$TMP/s2" "$TMP/seeds.txt"

    if [ ! -s "$TMP/seeds.txt" ]; then
      NOTE="No definition of \`$SYMBOL\` matched, so every file mentioning it is treated as a seed. Narrow with --file if this is too broad."
      if [ -n "$GREP_ALL" ]; then
        $GREP_ALL -w "$SYMBOL" . 2>/dev/null | cut -d: -f1 | sort -u > "$TMP/seeds.txt"
      else
        grep -rIlw "$SYMBOL" . 2>/dev/null | sed 's|^\./||' | sort -u > "$TMP/seeds.txt"
      fi
      sed 's|^\./||' "$TMP/seeds.txt" > "$TMP/s2" && mv "$TMP/s2" "$TMP/seeds.txt"
    fi
    if [ ! -s "$TMP/seeds.txt" ]; then
      printf 'blast-radius: `%s` does not appear anywhere in %s\n' "$SYMBOL" "$ROOT"
      exit 2
    fi

    # Every occurrence, so each affected file carries a line to jump to.
    if [ -n "$GREP_ALL" ]; then
      $GREP_ALL -w "$SYMBOL" . 2>/dev/null \
        | sed 's|^\./||' \
        | awk -F: 'NF>=3 { f=$1; l=$2; $1=""; $2=""; sub(/^::/,""); gsub(/^[ \t]+/,""); print f "\t" l "\t" $0 }' \
        > "$TMP/hits.txt"
    else
      grep -rInw "$SYMBOL" . 2>/dev/null \
        | sed 's|^\./||' \
        | awk -F: 'NF>=3 { f=$1; l=$2; $1=""; $2=""; sub(/^::/,""); gsub(/^[ \t]+/,""); print f "\t" l "\t" $0 }' \
        > "$TMP/hits.txt"
    fi
    ;;
esac

[ -n "$NOTE" ] && printf '%s\n\n' "$NOTE"

awk -f "$PLUGIN_ROOT/scripts/blast-radius.awk" \
    -v seeds="$TMP/seeds.txt" \
    -v edges="$OUT/imports.tsv" \
    -v unresolved="$OUT/unresolved.tsv" \
    -v hits="$TMP/hits.txt" \
    -v symbol="$SYMBOL" \
    -v depth="$DEPTH" \
    -v max="$MAX"
