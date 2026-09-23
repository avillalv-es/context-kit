#!/bin/sh
# code-graph - build the file-level import graph.
#
# Usage: code-graph.sh [--root DIR] [--out DIR] [--quiet]
#
# Writes <out>/imports.tsv    from<TAB>to<TAB>lang<TAB>form<TAB>confidence<TAB>line
#        <out>/unresolved.tsv from<TAB>module<TAB>reason<TAB>line
#        <out>/bindings.tsv   from<TAB>line<TAB>to<TAB>local<TAB>imported<TAB>kind<TAB>conf<TAB>flags<TAB>module
#                              - which NAME a JS/TS or Python import statement
#                              binds and to which resolved file (a subset of
#                              imports.tsv's edges; empty for every other
#                              language)
#
# File level, not symbol level, and that is the trade on purpose: an import
# line changes far less often than a function body, so this stays true longer
# than a symbol index would, and it needs no AST and no per-language resolver
# that has to understand dynamic dispatch. It answers "which file depends on
# which file". For "which function calls which function", grep is still the
# right tool and is never stale.

set -u

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SELF_DIR="."
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/.." 2>/dev/null && pwd)}"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
OUT=""
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)  ROOT="${2:-}"; shift 2 ;;
    --out)   OUT="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) shift ;;
  esac
done

ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { printf 'code-graph: no such directory\n' >&2; exit 1; }
[ -n "$OUT" ] || OUT="$ROOT/.claude/context-graph"
mkdir -p "$OUT" 2>/dev/null || { printf 'code-graph: cannot create %s\n' "$OUT" >&2; exit 1; }

SRC_RE='\.(js|jsx|mjs|cjs|ts|tsx|mts|cts|vue|svelte|astro|py|pyi|go|java|kt|kts|scala|groovy|cs|csproj|fsproj|vbproj|rs|rb|php|c|h|cpp|hpp|cc|hh|cxx|hxx|m|mm|sh|bash)$'

cd "$ROOT" || exit 1

# git ls-files where there is a work tree: it already honours .gitignore, so
# node_modules and vendor never enter the graph and never inflate a fan-in.
all_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # --cached AND --others: `git ls-files` alone lists only TRACKED files, so
    # a file you just created is absent from the graph as both a source and a
    # target - which is precisely the file you are most likely to be tracing.
    # --exclude-standard keeps .gitignore honoured, so node_modules stays out.
    git ls-files --cached --others --exclude-standard 2>/dev/null | sort -u && return 0
  fi
  find . -type f \
    ! -path './.git/*' ! -path './node_modules/*' ! -path './.venv/*' \
    ! -path './venv/*' ! -path './vendor/*' ! -path './dist/*' \
    ! -path './build/*' ! -path './target/*' ! -path './.claude/context-graph/*' \
    2>/dev/null | sed 's|^\./||'
}

TMP="$OUT/.tmp.cg.$$"
mkdir -p "$TMP" || exit 1
trap 'rm -rf "$TMP" 2>/dev/null' EXIT INT TERM

all_files > "$TMP/files.txt" 2>/dev/null
grep -Ei "$SRC_RE" "$TMP/files.txt" > "$TMP/src.txt" 2>/dev/null

NSRC="$(wc -l < "$TMP/src.txt" 2>/dev/null | tr -d ' ')"
[ -n "$NSRC" ] || NSRC=0
if [ "$NSRC" -eq 0 ]; then
  : > "$OUT/imports.tsv"
  : > "$OUT/unresolved.tsv"
  : > "$OUT/bindings.tsv"
  [ "$QUIET" -eq 1 ] || printf 'code-graph: no source files under %s\n' "$ROOT" >&2
  exit 0
fi

# go.mod supplies the prefix every internal Go import carries. Every go.mod,
# not just a root one: a repo whose module lives in a subdirectory, or which
# has several modules, resolves nothing at all from a root-only read - every
# internal import comes out looking like a third-party package.
: > "$TMP/gomods.tsv"
find . -type f -name 'go.mod' ! -path '*/vendor/*' ! -path './.git/*' 2>/dev/null \
  | sed 's|^\./||' | head -100 | while IFS= read -r GM; do
      [ -n "$GM" ] && [ -f "$GM" ] || continue
      MP="$(sed -n 's/^module[[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p' "$GM" 2>/dev/null | head -1)"
      [ -n "$MP" ] || continue
      SC="$(dirname "$GM")"
      [ "$SC" = "." ] && SC=""
      printf '%s\t%s\n' "$SC" "$MP"
    done >> "$TMP/gomods.tsv"

# Path aliases. A repo that uses "@/lib/x" everywhere resolves to nothing
# without these, and the graph comes out looking like the app has no edges.
#
# Every tsconfig/jsconfig, not just the root one: in a monorepo each package
# declares its own paths, and a root-only read leaves every package's
# internal imports unresolved.
#
# Parsed with awk, not sed piped into `while read`: the sed form drops the
# last entry whenever the JSON has no trailing newline, which is exactly the
# case after the newlines are squashed to parse across lines.
: > "$TMP/aliases.tsv"
find . -type f \( -name 'tsconfig.json' -o -name 'tsconfig.base.json' -o -name 'jsconfig.json' \) \
     ! -path '*/node_modules/*' ! -path './.git/*' 2>/dev/null \
  | sed 's|^\./||' | head -200 > "$TMP/tsconfigs.txt"
while IFS= read -r TSC; do
  [ -n "$TSC" ] && [ -f "$TSC" ] || continue
  SCOPE="$(dirname "$TSC")"
  [ "$SCOPE" = "." ] && SCOPE=""
  awk -v scope="$SCOPE" '
    { sub(/\r$/, ""); buf = buf " " $0 }
    END {
      # A config that does not "extends" another is self-contained, so an
      # alias the outer config declares does NOT apply to files under it.
      own = (buf ~ /"extends"[ \t]*:/) ? 0 : 1
      base = ""
      if (match(buf, /"baseUrl"[ \t]*:[ \t]*"[^"]*"/)) {
        base = substr(buf, RSTART, RLENGTH)
        sub(/^[^"]*"[^"]*"[ \t]*:[ \t]*"/, "", base); sub(/"$/, "", base)
        sub(/^\.\//, "", base); sub(/\/$/, "", base)
        if (base == ".") base = ""
      }
      if (!match(buf, /"paths"[ \t]*:[ \t]*\{[^}]*\}/)) exit
      blk = substr(buf, RSTART, RLENGTH)
      # A paths entry is a LIST of fallbacks and TypeScript tries each in
      # order, so reading only the first loses every alias whose first
      # candidate does not exist.
      while (match(blk, /"[^"]+"[ \t]*:[ \t]*\[[^]]*\]/)) {
        seg = substr(blk, RSTART, RLENGTH)
        blk = substr(blk, RSTART + RLENGTH)
        k = seg; sub(/"[ \t]*:.*$/, "", k); sub(/^"/, "", k)
        vals = seg; sub(/^[^[]*\[/, "", vals); sub(/\].*$/, "", vals)
        wild = (k ~ /\*$/) ? 1 : 0
        sub(/\*$/, "", k)
        if (k == "") continue
        while (match(vals, /"[^"]*"/)) {
          v = substr(vals, RSTART + 1, RLENGTH - 2)
          vals = substr(vals, RSTART + RLENGTH)
          sub(/\*$/, "", v); sub(/^\.\//, "", v)
          if (v == "") continue
          print scope "\t" k "\t" (base == "" ? v : base "/" v) "\t" wild "\t" own "\t" "ts"
        }
      }
    }
  ' "$TSC" >> "$TMP/aliases.tsv" 2>/dev/null
done < "$TMP/tsconfigs.txt"
# package.json "imports" declares #subpath specifiers, which resolve to real
# files and appear in application code exactly like an alias.
find . -type f -name 'package.json' ! -path '*/node_modules/*' ! -path './.git/*' \
     2>/dev/null | sed 's|^\./||' | head -200 > "$TMP/pkgjsons.txt"
while IFS= read -r PJ; do
  [ -n "$PJ" ] && [ -f "$PJ" ] || continue
  SCOPE="$(dirname "$PJ")"
  [ "$SCOPE" = "." ] && SCOPE=""
  awk -v scope="$SCOPE" '
    { sub(/\r$/, ""); buf = buf " " $0 }
    END {
      if (!match(buf, /"imports"[ \t]*:[ \t]*\{[^}]*\}/)) exit
      blk = substr(buf, RSTART, RLENGTH)
      while (match(blk, /"#[^"]*"[ \t]*:[ \t]*"[^"]*"/)) {
        seg = substr(blk, RSTART, RLENGTH)
        blk = substr(blk, RSTART + RLENGTH)
        k = seg; sub(/"[ \t]*:.*$/, "", k); sub(/^"/, "", k)
        v = seg; sub(/^.*:[ \t]*"/, "", v); sub(/"$/, "", v)
        wild = (k ~ /\*$/) ? 1 : 0
        sub(/\*$/, "", k); sub(/\*$/, "", v); sub(/^\.\//, "", v)
        if (k == "" || v == "") continue
        print scope "\t" k "\t" v "\t" wild "\t" "\t" "pkg"
      }
    }
  ' "$PJ" >> "$TMP/aliases.tsv" 2>/dev/null
done < "$TMP/pkgjsons.txt"

# composer PSR-4 does the same job for PHP. It shares aliases.tsv with the
# tsconfig/package.json entries above, but is tagged "psr4" (6th column) so
# the JS resolver's bindings `alias` flag - reserved for a tsconfig/jsconfig
# paths entry or a package.json imports entry - is never set through it, even
# when a PSR-4 prefix happens to also resolve a bare JS specifier.
if [ -f composer.json ]; then
  awk '
    { sub(/\r$/, ""); buf = buf " " $0 }
    END {
      if (!match(buf, /"psr-4"[ \t]*:[ \t]*\{[^}]*\}/)) exit
      blk = substr(buf, RSTART, RLENGTH)
      while (match(blk, /"[^"]*"[ \t]*:[ \t]*"[^"]*"/)) {
        seg = substr(blk, RSTART, RLENGTH)
        blk = substr(blk, RSTART + RLENGTH)
        k = seg; sub(/"[ \t]*:.*$/, "", k); sub(/^"/, "", k)
        v = seg; sub(/^.*:[ \t]*"/, "", v); sub(/"$/, "", v)
        gsub(/\\\\/, "/", k)
        sub(/\/$/, "", k)
        sub(/^\.\//, "", v); sub(/\/$/, "", v)
        if (k == "") continue
        print "\t" k "/\t" v "/\t1" "\t" "\t" "psr4"
      }
    }
  ' composer.json >> "$TMP/aliases.tsv" 2>/dev/null
fi

: > "$TMP/unresolved.tsv"
: > "$TMP/bindings.tsv"
awk -f "$PLUGIN_ROOT/scripts/common.awk" -f "$PLUGIN_ROOT/scripts/code-graph.awk" \
    -v filelist="$TMP/files.txt" \
    -v root="$ROOT" \
    -v gomods="$TMP/gomods.tsv" \
    -v aliases="$TMP/aliases.tsv" \
    -v unresolved="$TMP/unresolved.tsv" \
    -v bindings="$TMP/bindings.tsv" \
    < "$TMP/src.txt" > "$TMP/imports.tsv" 2> "$TMP/stats.txt"

sort -u "$TMP/imports.tsv" > "$OUT/imports.tsv" 2>/dev/null || cp "$TMP/imports.tsv" "$OUT/imports.tsv"
sort -u "$TMP/unresolved.tsv" > "$OUT/unresolved.tsv" 2>/dev/null || cp "$TMP/unresolved.tsv" "$OUT/unresolved.tsv"
sort -u "$TMP/bindings.tsv" > "$OUT/bindings.tsv" 2>/dev/null || cp "$TMP/bindings.tsv" "$OUT/bindings.tsv"

if [ "$QUIET" -eq 0 ]; then
  NE="$(wc -l < "$OUT/imports.tsv" | tr -d ' ')"
  NU="$(wc -l < "$OUT/unresolved.tsv" | tr -d ' ')"
  printf '%s source files, %s import edges, %s unresolved\n' "$NSRC" "$NE" "$NU"
  printf 'wrote %s/imports.tsv\n' "$OUT"
fi
exit 0
