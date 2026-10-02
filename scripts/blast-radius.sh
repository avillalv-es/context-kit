#!/bin/sh
# blast-radius - what breaks if this changes.
#
# Usage:
#   blast-radius.sh <symbol>               trace a function, class or constant
#   blast-radius.sh <symbol> --file <path> ...defined in that one file
#   blast-radius.sh --file <path>          trace a file
#   blast-radius.sh --diff [--base REF]    trace everything changed in the tree
#
#   --depth N     hops to walk back (default 3)
#   --max N       rows per depth (default 40)
#   --cached      reuse the existing import graph instead of rebuilding
#   --root DIR    project root (default: $CLAUDE_PROJECT_DIR, else the cwd)
#   --out DIR     where the graph is written (default: <root>/.claude/context-graph)
#
# Exit codes: 0 ok (including "nothing changed"), 1 usage error or the graph
# could not be built or an unknown --base, 2 the symbol appears nowhere.
#
# Output: the first line is
#   blast-radius: seeds=<n> affected=<n> depth=<d> edges=<e> gaps=<k>
# then these `## ` sections, each only when it has something to say (Seeds
# always): Seeds, Depth 1.., Name matches, Tests to run, Blind spots. A row is
# `path:line -> via`, tagged `[inferred import, verify]` when the edge came from
# an alias or a suffix match. The report ends with an unconditional caveat.
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
START_DIR="$PWD"
TAB="$(printf '\t')"
OUT=""
DEPTH=3
MAX=40
CACHED=0
HELP=0
DIFF=0
SYMBOL=""
FILEARG=""
BASE=""
NPOS=0

die() { printf 'blast-radius: %s\n' "$1" >&2; exit 1; }
bad() { printf 'blast-radius: %s\n(blast-radius.sh --help shows the usage)\n' "$1" >&2; exit 1; }
need() {
  [ $# -ge 2 ] || bad "$1 needs a value"
  case "$2" in ''|-*) bad "$1 needs a value, not '$2'" ;; esac
}

usage() {
  cat <<'HELP'
blast-radius - what breaks if this changes

  blast-radius.sh <symbol>                trace a function, class or constant
  blast-radius.sh <symbol> --file <path>  ...as defined in that one file
  blast-radius.sh --file <path>           trace a file
  blast-radius.sh --diff                  trace everything changed in the tree
  blast-radius.sh --diff --base main      ...changed since branching from main

  --depth N   hops to walk back (default 3)
  --max N     rows shown per depth (default 40)
  --cached    reuse the existing import graph instead of rebuilding
  --root DIR  project root; --out DIR where the graph goes

--diff covers staged, unstaged and untracked work, and treats a deleted file
(or the old path of a rename) as a seed, because deleting is when importers
break. --base REF diffs from the merge-base with REF.

Exit codes: 0 ok or nothing changed; 1 usage error, unknown --base, or the
graph could not be built; 2 the symbol appears nowhere.

File level: it follows imports, so it sees what depends on what. It cannot
see runtime wiring - route tables, DI containers, plugin registries - and
says so in the report rather than leaving you to assume it looked.
HELP
}

while [ $# -gt 0 ]; do
  case "$1" in
    --file=*|--base=*|--depth=*|--max=*|--root=*|--out=*)
      a="$1"; shift; set -- "${a%%=*}" "${a#*=}" "$@"; continue ;;
  esac
  case "$1" in
    --file)   need "$@"; FILEARG="$2"; shift 2 ;;
    --base)   need "$@"; BASE="$2"; shift 2 ;;
    --depth)  need "$@"; DEPTH="$2"; shift 2 ;;
    --max)    need "$@"; MAX="$2"; shift 2 ;;
    --root)   need "$@"; ROOT="$2"; shift 2 ;;
    --out)    need "$@"; OUT="$2"; shift 2 ;;
    --diff)   DIFF=1; shift ;;
    --cached) CACHED=1; shift ;;
    -h|--help) HELP=1; shift ;;
    -*)       bad "unknown option: $1" ;;
    *)
      NPOS=$((NPOS + 1))
      [ "$NPOS" -le 1 ] || bad "one symbol or path at a time, got '$SYMBOL' and '$1'"
      SYMBOL="$1"; shift ;;
  esac
done

if [ "$HELP" -eq 1 ]; then usage; exit 0; fi

case "$DEPTH" in ''|*[!0-9]*|0) bad "--depth must be a positive number, not '$DEPTH'" ;; esac
case "$MAX" in ''|*[!0-9]*|0) bad "--max must be a positive number, not '$MAX'" ;; esac

# A relative --out is relative to where the command was typed, not to --root.
case "$OUT" in
  ""|/*|[A-Za-z]:*) : ;;
  *) OUT="$START_DIR/$OUT" ;;
esac

ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || die "no such directory: $ROOT"
[ -n "$OUT" ] || OUT="$ROOT/.claude/context-graph"
cd "$ROOT" || exit 1

# --- decide the mode -----------------------------------------------------------
# A bare argument that is a path - it has a slash, or it names a file that
# exists - is a file, not a symbol.
norm_path() {
  p="$(printf '%s' "$1" | tr '\\' '/')"
  case "$p" in
    [A-Za-z]:/*)
      if command -v cygpath >/dev/null 2>&1; then p="$(cygpath -u "$p" 2>/dev/null || printf '%s' "$p")"; fi ;;
  esac
  case "$p" in "$ROOT"/*) p="${p#"$ROOT"/}" ;; esac
  while :; do
    case "$p" in ./*) p="${p#./}" ;; *) break ;; esac
  done
  printf '%s' "$p"
}

if [ -n "$SYMBOL" ] && [ -z "$FILEARG" ] && [ "$DIFF" -eq 0 ]; then
  case "$SYMBOL" in
    */*|*\\*) FILEARG="$SYMBOL"; SYMBOL="" ;;
    *) [ -f "$SYMBOL" ] && { FILEARG="$SYMBOL"; SYMBOL=""; } ;;
  esac
fi

if [ "$DIFF" -eq 1 ]; then
  { [ -z "$SYMBOL" ] && [ -z "$FILEARG" ]; } || bad "--diff cannot be combined with a symbol or --file"
  MODE=diff
elif [ -n "$SYMBOL" ]; then
  MODE=symbol
elif [ -n "$FILEARG" ]; then
  MODE=file
else
  usage >&2
  exit 1
fi
{ [ -z "$BASE" ] || [ "$MODE" = diff ]; } || bad "--base only applies to --diff"

if [ "$MODE" = symbol ]; then
  case "$SYMBOL" in
    *[!A-Za-z0-9_.\$-]*|-*) bad "$SYMBOL does not look like a symbol" ;;
  esac
fi
if [ -n "$FILEARG" ]; then
  FILEARG="$(norm_path "$FILEARG")"
  case "$FILEARG" in /*|[A-Za-z]:*) die "$FILEARG is outside the project root $ROOT" ;; esac
  [ -f "$FILEARG" ] || die "no such file: $FILEARG"
fi

INGIT=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && INGIT=1
if [ "$MODE" = diff ] && [ "$INGIT" -eq 0 ]; then
  die "--diff needs a git work tree; $ROOT is not inside one"
fi

OUT_REL=""
case "$OUT" in "$ROOT"/*) OUT_REL="${OUT#"$ROOT"/}" ;; esac

TMP="$OUT/.tmp.br.$$"
mkdir -p "$TMP" || die "cannot create $TMP"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
: > "$TMP/seeds.txt"
: > "$TMP/extras.txt"
: > "$TMP/notes.txt"
: > "$TMP/hits.txt"

# Search the work tree. Inside git it is `git grep`, which honours .gitignore
# and needs no ripgrep (on Windows `rg` is often a shell function a child sh
# cannot see). Outside git it is grep -r with the output and vendor
# directories excluded explicitly, so it never reads its own graph.
gsearch() {
  if [ "$INGIT" -eq 1 ]; then
    if [ -n "$OUT_REL" ]; then
      git grep -n -I --untracked "$@" -- . ':(exclude).claude/context-graph' ":(exclude)$OUT_REL" 2>/dev/null
    else
      git grep -n -I --untracked "$@" -- . ':(exclude).claude/context-graph' 2>/dev/null
    fi
  else
    grep -rnI --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist \
      --exclude-dir=build --exclude-dir=context-graph --exclude-dir='.tmp.br.*' \
      "$@" . 2>/dev/null | sed 's|^\./||'
  fi
}

case "$MODE" in
  file)
    printf '%s\t\n' "$FILEARG" > "$TMP/seeds.txt"
    ;;

  diff)
    # The audit and debugging case: you already changed things, and the
    # question is what else you now have to look at.
    if [ -n "$BASE" ]; then
      git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 || die "unknown base ref: $BASE"
      REF="$(git merge-base "$BASE" HEAD 2>/dev/null)"
      [ -n "$REF" ] || die "no merge base between $BASE and HEAD (is the clone shallow?)"
    elif git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
      REF=HEAD
    else
      REF="$(git hash-object -t tree /dev/null)"
    fi
    # Committed, staged and unstaged changes since REF in one view, relative to
    # the project root so a root below the repository's top level still works.
    git -c core.quotePath=false diff --name-status -M --relative "$REF" -- . \
      > "$TMP/changed.txt" 2> "$TMP/giterr" || die "git diff failed: $(head -n 1 "$TMP/giterr")"
    {
      awk 'BEGIN { FS = "\t" }
        { s = substr($1, 1, 1)
          if (s == "R") { printf "%s\trenamed to %s\n", $2, $3; printf "%s\trenamed from %s\n", $3, $2 }
          else if (s == "C") printf "%s\tcopied from %s\n", $3, $2
          else if (s == "D") printf "%s\tdeleted\n", $2
          else printf "%s\t\n", $2 }' "$TMP/changed.txt"
      # Untracked files too. A new file is the most common thing an audit adds,
      # and `git diff` never mentions it.
      git -c core.quotePath=false ls-files --others --exclude-standard 2>/dev/null
    } | LC_ALL=C sort -t "$TAB" -k1,1 > "$TMP/changed.sorted"

    PREV=""
    while IFS="$TAB" read -r P TAG; do
      [ -n "$P" ] || continue
      [ "$P" != "$PREV" ] || continue
      PREV="$P"
      case "$P" in .git/*|.claude/context-graph/*) continue ;; esac
      if [ -n "$OUT_REL" ]; then case "$P" in "$OUT_REL"/*) continue ;; esac; fi
      [ -d "$P" ] && continue
      if [ -f "$P" ]; then
        case "$TAG" in deleted*|"renamed to"*) TAG="" ;; esac
      else
        # Gone from disk: deleted, or the old path of a rename. This is the
        # file whose importers break, so it stays a seed.
        [ -n "$TAG" ] || TAG="deleted"
        printf '%s\n' "$P" >> "$TMP/extras.txt"
      fi
      printf '%s\t%s\n' "$P" "$TAG" >> "$TMP/seeds.txt"
    done < "$TMP/changed.sorted"

    if [ ! -s "$TMP/seeds.txt" ]; then
      printf 'blast-radius: seeds=0 affected=0 depth=0 edges=0 gaps=0\n\n## Seeds\nnote: nothing changed%s - nothing to trace\n' \
        "$([ -n "$BASE" ] && printf ' against %s' "$BASE")"
      exit 0
    fi
    ;;

  symbol)
    gsearch -w -F -e "$SYMBOL" 2>/dev/null | head -n 20000 | tr -d '\r' \
      | sed "s/^\([^:]*\):\([0-9][0-9]*\):/\1${TAB}\2${TAB}/" \
      | LC_ALL=C sort -t "$TAB" -k1,1 -k2,2n > "$TMP/hits.txt"
    if [ ! -s "$TMP/hits.txt" ]; then
      printf 'blast-radius: `%s` does not appear anywhere in %s\n' "$SYMBOL" "$ROOT"
      exit 2
    fi

    if [ -n "$FILEARG" ]; then
      # The caller named the defining file, so there is nothing to guess.
      if ! grep -qwF -e "$SYMBOL" -- "$FILEARG" 2>/dev/null; then
        printf 'blast-radius: `%s` does not appear in %s\n' "$SYMBOL" "$FILEARG"
        exit 2
      fi
      printf '%s\t\n' "$FILEARG" > "$TMP/seeds.txt"
      printf 'scoped to the definition in %s\n' "$FILEARG" >> "$TMP/notes.txt"
    else
      # Seed on the DEFINITION, not on every mention: tracing from every file
      # that says the word makes the walk start everywhere and mean nothing.
      # The symbol is escaped, and the patterns name what may sit right before
      # it, so `extends SYM` and `implements SYM` are uses, not definitions.
      SYM_ESC="$(printf '%s' "$SYMBOL" | sed 's,[][\.*^$+?(){}|/],\\&,g')"
      B='[^[:alnum:]_$]'
      LEAD="(^|$B)"
      TRAIL="($B|\$)"
      KW='(function|class|interface|enum|struct|trait|type|typealias|def|fn|func|fun|val|var|let|const|object|record|module|namespace|protocol|actor|union|mod)'
      MOD='(public|private|protected|internal|static|abstract|virtual|override|sealed|async|final|readonly|extern|unsafe|partial|synchronized|open|suspend|inline|operator|tailrec|lateinit)'
      # keyword + name: function/class/def/fn/fun/val/type..., with an optional
      # generic list or receiver (Kotlin `fun <T> Foo.name`, Ruby `def self.name`)
      D1="$LEAD$KW[[:space:]]+(<[^>]*>[[:space:]]*)?([[:alnum:]_.]+\.)?$SYM_ESC$TRAIL"
      D2="${LEAD}function\*[[:space:]]*$SYM_ESC$TRAIL"
      # modifier-led members: `public static Task<Foo> name(`, `private name: T`
      D3="$LEAD$MOD[[:space:]]+([^=;(){}:]*[[:space:]])?$SYM_ESC[[:space:]]*(\(|<|\{|;|=|:|\?|\$)"
      # Go methods: func (r *T) name(
      D4="${LEAD}func[[:space:]]*\([^)]*\)[[:space:]]*$SYM_ESC[[:space:]]*(\(|\[)"
      # name = function / name: (...) =>, and a top-level Python/shell assignment
      D5="$LEAD$SYM_ESC[[:space:]]*[:=][[:space:]]*(function|async|\(|class|new[[:space:]])"
      D6="^$SYM_ESC[[:space:]]*(:[^=]+)?=([^=]|\$)"
      D7="^[[:space:]]*#[[:space:]]*define[[:space:]]+$SYM_ESC$TRAIL"
      gsearch -E -e "$D1" -e "$D2" -e "$D3" -e "$D4" -e "$D5" -e "$D6" -e "$D7" \
        | tr -d '\r' \
        | awk -v sym="$SYMBOL" '
            function wordat(text, off, rest, pos, a, b) {
              rest = text; off = 0
              while ((pos = index(rest, sym)) > 0) {
                a = (off + pos > 1) ? substr(text, off + pos - 1, 1) : ""
                b = substr(text, off + pos + length(sym), 1)
                if (a !~ /[A-Za-z0-9_$]/ && b !~ /[A-Za-z0-9_$]/) {
                  pre = substr(text, 1, off + pos - 1)
                  if (pre !~ /(^|[^A-Za-z0-9_$])(extends|implements|throws|new|return|inherits|where|import|from|with)[ \t]/) return 1
                }
                off += pos
                rest = substr(text, off + 1)
              }
              return 0
            }
            {
              i = index($0, ":"); if (!i) next
              path = substr($0, 1, i - 1); rest = substr($0, i + 1)
              j = index(rest, ":"); if (!j) next
              text = substr(rest, j + 1)
              if (path !~ /\.(js|jsx|mjs|cjs|ts|tsx|mts|cts|vue|svelte|astro|py|pyi|go|java|kt|kts|scala|groovy|cs|rs|rb|php|c|h|cpp|hpp|cc|hh|cxx|hxx|m|mm|sh|bash)$/) next
              t = text; sub(/^[ \t]+/, "", t)
              if (t ~ /^(\/\/|\/\*|\*|#[ \t!]|#$|--[ \t])/) next
              if (t ~ /^(import[ \t{*]|from[ \t]|export[ \t]*(type[ \t]*)?[{*])/) next
              if (text ~ /=[ \t]*(await[ \t]+)?(require|import)[ \t]*\(/) next
              if (wordat(text)) print path
            }' \
        | LC_ALL=C sort -u > "$TMP/defs.txt"
      if [ -s "$TMP/defs.txt" ]; then
        sed "s/\$/${TAB}/" "$TMP/defs.txt" > "$TMP/seeds.txt"
      else
        cut -f1 "$TMP/hits.txt" | LC_ALL=C sort -u | sed "s/\$/${TAB}/" > "$TMP/seeds.txt"
        printf 'No definition of `%s` matched, so every file that mentions it is a seed. Narrow with `%s --file <path>`.\n' \
          "$SYMBOL" "$SYMBOL" >> "$TMP/notes.txt"
      fi
    fi
    ;;
esac

# --- the import graph ----------------------------------------------------------
# A deleted or renamed-away path is not in the work tree, so no import resolves
# to it and its importers would vanish from the graph. Hand those paths to the
# extractor as extra members of the file set (never scanned), and build into
# the scratch directory so the shared graph never holds edges to files that
# are not there.
GRAPH="$OUT"
BUILD=1
if [ "$CACHED" -eq 1 ] && [ -f "$OUT/imports.tsv" ]; then BUILD=0; fi
EXTRA=""
if [ -s "$TMP/extras.txt" ]; then
  EXTRA="$TMP/extras.txt"
  GRAPH="$TMP/graph"
  if [ "$BUILD" -eq 0 ]; then
    printf '%s\n' "--cached ignored: a deleted path needs a fresh graph" >> "$TMP/notes.txt"
  fi
  BUILD=1
fi
if [ "$BUILD" -eq 1 ]; then
  CODE_GRAPH_EXTRA_FILES="$EXTRA" sh "$PLUGIN_ROOT/scripts/code-graph.sh" \
    --root "$ROOT" --out "$GRAPH" --quiet || die "could not build the import graph"
fi
[ -f "$GRAPH/imports.tsv" ] || die "no import graph at $GRAPH"

awk -f "$PLUGIN_ROOT/scripts/blast-radius.awk" \
    -v seeds="$TMP/seeds.txt" \
    -v edges="$GRAPH/imports.tsv" \
    -v unresolved="$GRAPH/unresolved.tsv" \
    -v hits="$TMP/hits.txt" \
    -v notes="$TMP/notes.txt" \
    -v symbol="$SYMBOL" \
    -v depth="$DEPTH" \
    -v max="$MAX" \
    -v sortfile="$TMP/sorted.txt" > "$TMP/report.txt" || die "could not build the report"
cat "$TMP/report.txt"
exit 0
