#!/bin/sh
# code-graph - build the file-level import graph.
#
# Usage: code-graph.sh [--root DIR] [--out DIR] [--quiet]
#
# Writes <out>/imports.tsv    from<TAB>to<TAB>lang<TAB>form<TAB>confidence<TAB>line
#        <out>/unresolved.tsv from<TAB>module<TAB>reason<TAB>line
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
# Every tsconfig*.json and jsconfig*.json, not just the root tsconfig.json:
# in a monorepo each package declares its own paths, and create-vue keeps
# its `@/*` in tsconfig.app.json while tsconfig.json holds only `references`.
# Every vite.config.{ts,js,mjs,mts} contributes its literal resolve.alias too.
#
# One awk pass over the whole list. It is written to a file from a quoted
# heredoc so that the quote characters a Vite config is full of never have to
# be escaped through the shell. An alias the awk cannot read as a literal is
# skipped; a skipped alias costs an edge, an invented one costs trust.
: > "$TMP/aliases.tsv"
find . -type f \( -name 'tsconfig*.json' -o -name 'jsconfig*.json' \
     -o -name 'vite.config.ts' -o -name 'vite.config.js' \
     -o -name 'vite.config.mjs' -o -name 'vite.config.mts' \) \
     ! -path '*/node_modules/*' ! -path './.git/*' 2>/dev/null \
  | sed 's|^\./||' | sort | head -600 > "$TMP/tsconfigs.txt"
cat > "$TMP/aliases-js.awk" <<'ALIAS_AWK'
# stdin:  repo-relative config paths, one per line
# stdout: scope<TAB>key<TAB>target<TAB>wild<TAB>own
#         scope  directory the config lives in ("" = repo root); the alias applies below it
#         target relative to scope, "/"-terminated when wild
#         own    1 when the config extends nothing, so outer aliases do not reach its files

function dirname(p,   d) { d = p; if (d !~ /\//) return ""; sub(/\/[^\/]*$/, "", d); return d }
function basename(p,   b) { b = p; sub(/.*\//, "", b); return b }
function joinp(a, b) { return (a == "") ? b : a "/" b }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

# Collapse "." and "..". nbad is set when the path climbs above the repo root,
# because "" alone cannot tell the root from an error.
function norm(p,   n, parts, out, i, k) {
  nbad = 0
  gsub(/\/+/, "/", p)
  n = split(p, parts, "/")
  k = 0
  for (i = 1; i <= n; i++) {
    if (parts[i] == "" || parts[i] == ".") continue
    if (parts[i] == "..") {
      if (k == 0) { nbad = 1; return "" }
      k--
      continue
    }
    out[++k] = parts[i]
  }
  p = ""
  for (i = 1; i <= k; i++) p = p (i > 1 ? "/" : "") out[i]
  return p
}

# Path from directory `from` to `to`, both repo-relative and normalised.
function relto(from, to,   fa, ta, nf, nt, i, c, out) {
  nf = (from == "") ? 0 : split(from, fa, "/")
  nt = (to == "") ? 0 : split(to, ta, "/")
  c = 0
  while (c < nf && c < nt && fa[c + 1] == ta[c + 1]) c++
  out = ""
  for (i = c + 1; i <= nf; i++) out = out "../"
  for (i = c + 1; i <= nt; i++) out = out ta[i] (i < nt ? "/" : "")
  return out
}

function row(sc, k, t, w, o,   r) {
  r = sc "\t" k "\t" t "\t" w "\t" o
  if (r in seenrow) return
  seenrow[r] = 1
  print r
}

# --- reading -------------------------------------------------------------
# True when a "/" after text `s` begins a regular expression rather than a
# division: at the start, or after an operator or an opening bracket.
function regex_ctx(s,   t) {
  t = s; sub(/[ \t]+$/, "", t)
  if (t == "") return 1
  return (substr(t, length(t), 1) ~ /[(,=:\[{!&|?;~^%+*<>-]/)
}

# Index of the "/" that closes the regex literal opening at position i, or 0.
function regex_end(s, i,   n, k, c, cls) {
  n = length(s); cls = 0
  for (k = i + 1; k <= n; k++) {
    c = substr(s, k, 1)
    if (c == "\\") { k++; continue }
    if (cls) { if (c == "]") cls = 0; continue }
    if (c == "[") { cls = 1; continue }
    if (c == "/") return k
  }
  return 0
}

# Comments out, newlines folded to spaces, quote-aware: "@/*" is a key, not
# the start of a block comment, and `// "paths": {...}` is a comment, not a
# config. js=1 also honours ' and ` as quotes, and swaps a regex literal for
# a 0: `find: /^@\//` holds a "//" that is no comment, and a `[(]` that is no
# bracket.
function uncomment(line, js,   i, n, c, q, out, j) {
  out = ""; q = ""; n = length(line); i = 1
  while (i <= n) {
    c = substr(line, i, 1)
    if (blk) {
      if (substr(line, i, 2) == "*/") { blk = 0; i += 2 } else i++
      continue
    }
    if (q != "") {
      out = out c
      if (c == "\\") { out = out substr(line, i + 1, 1); i += 2; continue }
      if (c == q) q = ""
      i++
      continue
    }
    if (js && c == "/" && substr(line, i + 1, 1) !~ /[\/*]/ && regex_ctx(out)) {
      j = regex_end(line, i)
      if (j > 0) {
        out = out "0"
        i = j + 1
        while (substr(line, i, 1) ~ /[a-z]/) i++
        continue
      }
    }
    if (c == "\"" || (js && (c == "'" || c == "`"))) { q = c; out = out c; i++; continue }
    if (substr(line, i, 2) == "//") break
    if (substr(line, i, 2) == "/*") { blk = 1; out = out " "; i += 2; continue }
    out = out c
    i++
  }
  return out
}

function slurp(path, js,   line, out, first) {
  out = ""; blk = 0; first = 1
  while ((getline line < path) > 0) {
    if (first) { sub(/^\357\273\277/, "", line); first = 0 }
    sub(/\r$/, "", line)
    out = out " " uncomment(line, js)
  }
  close(path)
  return out
}

# --- tsconfig / jsconfig -------------------------------------------------
# `extends` is followed ONE level, and only for a relative path: a package
# such as @vue/tsconfig lives in node_modules and is not read. The extending
# config's compilerOptions.paths replaces the base's, as in TypeScript, and
# baseUrl is resolved from the directory of the file that declares it.
function do_ts(path,   sc, selfb, own, ev, s, bp, bb, nf, files, bufs, i, fd, b, hasbase, ebase, basebad, haspaths, pblk, pdir, bu, rbase, blk2, seg, k, vals, wild, v, t, rel) {
  sc = dirname(path)
  selfb = slurp(path, 0)
  if (selfb == "") return
  # A config that extends nothing is self-contained, so an alias the outer
  # config declares does NOT apply to files under it.
  own = (selfb ~ /"extends"[ \t]*:/) ? 0 : 1
  nf = 0
  split("", files); split("", bufs)
  if (match(selfb, /"extends"[ \t]*:[ \t]*("[^"]*"|\[[^]]*\])/)) {
    ev = substr(selfb, RSTART, RLENGTH)
    sub(/^"extends"[ \t]*:[ \t]*/, "", ev)
    while (match(ev, /"[^"]*"/)) {
      s = substr(ev, RSTART + 1, RLENGTH - 2)
      ev = substr(ev, RSTART + RLENGTH)
      if (s !~ /^\.\.?\//) continue
      if (s !~ /\.json$/) s = s ".json"
      bp = norm(joinp(sc, s))
      if (nbad || bp == "") continue
      bb = slurp(bp, 0)
      if (bb == "") continue
      files[++nf] = bp; bufs[nf] = bb
    }
  }
  files[++nf] = path; bufs[nf] = selfb
  hasbase = 0; basebad = 0; haspaths = 0; ebase = ""; pblk = ""; pdir = ""
  for (i = 1; i <= nf; i++) {
    fd = dirname(files[i]); b = bufs[i]
    if (match(b, /"baseUrl"[ \t]*:[ \t]*"[^"]*"/)) {
      bu = substr(b, RSTART, RLENGTH)
      sub(/^"baseUrl"[ \t]*:[ \t]*"/, "", bu); sub(/"$/, "", bu)
      hasbase = 1
      if (bu ~ /\$\{/ || bu ~ /^\//) basebad = 1
      else { ebase = norm(joinp(fd, bu)); basebad = nbad }
    }
    if (match(b, /"paths"[ \t]*:[ \t]*\{[^}]*\}/)) { pblk = substr(b, RSTART, RLENGTH); pdir = fd; haspaths = 1 }
  }
  if (!haspaths || basebad) return
  # paths resolve against baseUrl when there is one, else against the
  # directory of the config that declares them.
  rbase = hasbase ? ebase : pdir
  blk2 = pblk
  # A paths entry is a LIST of fallbacks and TypeScript tries each in order,
  # so reading only the first loses every alias whose first candidate does
  # not exist.
  while (match(blk2, /"[^"]+"[ \t]*:[ \t]*\[[^]]*\]/)) {
    seg = substr(blk2, RSTART, RLENGTH)
    blk2 = substr(blk2, RSTART + RLENGTH)
    k = seg; sub(/"[ \t]*:.*$/, "", k); sub(/^"/, "", k)
    vals = seg; sub(/^[^[]*\[/, "", vals); sub(/\].*$/, "", vals)
    wild = (k ~ /\*$/) ? 1 : 0
    sub(/\*$/, "", k)
    if (k == "" || k ~ /\*/) continue
    while (match(vals, /"[^"]*"/)) {
      v = substr(vals, RSTART + 1, RLENGTH - 2)
      vals = substr(vals, RSTART + RLENGTH)
      if (wild) { if (v !~ /\*$/) continue; sub(/\*$/, "", v) }
      if (v ~ /\*/ || v ~ /\$\{/ || v ~ /^\//) continue
      t = norm(joinp(rbase, v))
      if (nbad) continue
      rel = relto(sc, t)
      if (wild) rel = (rel == "") ? "./" : rel "/"
      else if (rel == "") continue
      row(sc, k, rel, wild, own)
    }
  }
}

# --- vite.config ---------------------------------------------------------
# Index of the bracket that closes the one opening at position i, or 0.
function match_close(s, i,   n, k, c, depth, q) {
  n = length(s); depth = 0; q = ""
  for (k = i; k <= n; k++) {
    c = substr(s, k, 1)
    if (q != "") {
      if (c == "\\") k++
      else if (c == q) q = ""
      continue
    }
    if (c == "'" || c == "\"" || c == "`") { q = c; continue }
    if (c == "{" || c == "[" || c == "(") depth++
    else if (c == "}" || c == "]" || c == ")") { depth--; if (depth == 0) return k }
  }
  return 0
}

# Split on commas that are not inside a bracket or a string.
function split_top(s, arr,   n, k, c, depth, q, cur, cnt) {
  split("", arr)
  cnt = 0; cur = ""; depth = 0; q = ""; n = length(s)
  for (k = 1; k <= n; k++) {
    c = substr(s, k, 1)
    if (q != "") {
      cur = cur c
      if (c == "\\") { k++; cur = cur substr(s, k, 1) }
      else if (c == q) q = ""
      continue
    }
    if (c == "'" || c == "\"" || c == "`") { q = c; cur = cur c; continue }
    if (c == "{" || c == "[" || c == "(") depth++
    else if (c == "}" || c == "]" || c == ")") depth--
    if (c == "," && depth == 0) { arr[++cnt] = cur; cur = ""; continue }
    cur = cur c
  }
  if (cur ~ /[^ \t]/) arr[++cnt] = cur
  return cnt
}

# The text of a plain '...' or "..." literal, else "".
function strlit(s,   q, r) {
  q = substr(s, 1, 1)
  if (q != "'" && q != "\"") return ""
  if (length(s) < 2 || substr(s, length(s), 1) != q) return ""
  r = substr(s, 2, length(s) - 2)
  if (index(r, q) > 0 || index(r, "\\") > 0) return ""
  return r
}

# An alias value as a path relative to the config's directory, or "" when it
# is anything but one of the literal forms below. Not evaluated, matched.
function vite_rel(v,   t, s, core, p, out) {
  t = trim(v)
  # '/src' - Vite reads it from the project root.
  s = strlit(t)
  if (s != "") {
    if (s ~ /^\/[^\/]/ && s !~ /\$\{/) return substr(s, 2)
    return ""
  }
  # fileURLToPath(new URL('./src', import.meta.url))  and  new URL(...).pathname
  core = "new[ \t]+URL[ \t]*\\([ \t]*['\"][^'\"]+['\"][ \t]*,[ \t]*import\\.meta\\.url[ \t]*\\)"
  if (t ~ ("^fileURLToPath[ \t]*\\([ \t]*" core "[ \t]*\\)$") || t ~ ("^" core "\\.pathname$")) {
    match(t, /URL[ \t]*\([ \t]*['"][^'"]+['"]/)
    p = substr(t, RSTART, RLENGTH)
    sub(/^URL[ \t]*\([ \t]*['"]/, "", p); sub(/['"]$/, "", p)
    if (p ~ /^\// || p ~ /:/ || p ~ /\$\{/) return ""
    return p
  }
  # path.resolve(__dirname, 'src')  /  path.join(__dirname, 'src', 'lib')
  if (t ~ /^(path\.)?(resolve|join)[ \t]*\([ \t]*(__dirname|import\.meta\.dirname)[ \t]*(,[ \t]*['"][^'"]*['"][ \t]*)+\)$/) {
    sub(/^[^,]*,/, "", t); sub(/\)[ \t]*$/, "", t)
    out = ""
    while (match(t, /['"][^'"]*['"]/)) {
      s = substr(t, RSTART + 1, RLENGTH - 2)
      t = substr(t, RSTART + RLENGTH)
      if (s ~ /^\// || s ~ /\$\{/) return ""
      if (s == "") continue
      out = (out == "") ? s : out "/" s
    }
    return out
  }
  return ""
}

# Vite matches a string key against the import itself and against `key/...`,
# so each alias becomes an exact row plus a wild row on `key/`.
function vite_entries(sc, inner, arr,   n, i, e, key, val, nn, j, f, q, rest, p, rel, t) {
  n = split_top(inner, ent)
  for (i = 1; i <= n; i++) {
    e = trim(ent[i])
    key = ""; val = ""
    if (arr) {
      # [{ find: '@', replacement: <expr> }]
      if (e !~ /^\{/) continue
      e = substr(e, 2); sub(/\}[ \t]*$/, "", e)
      nn = split_top(e, fld)
      for (j = 1; j <= nn; j++) {
        f = trim(fld[j])
        if (f ~ /^find[ \t]*:/) key = strlit(trim(substr(f, index(f, ":") + 1)))
        else if (f ~ /^replacement[ \t]*:/) val = trim(substr(f, index(f, ":") + 1))
      }
    } else {
      # 'key': <expr>   "key": <expr>   key: <expr>
      q = substr(e, 1, 1)
      if (q == "'" || q == "\"") {
        rest = substr(e, 2)
        p = index(rest, q)
        if (p == 0) continue
        key = substr(rest, 1, p - 1)
        rest = trim(substr(rest, p + 1))
        if (substr(rest, 1, 1) != ":") continue
        val = trim(substr(rest, 2))
      } else if (match(e, /^[A-Za-z_$][A-Za-z0-9_$]*[ \t]*:/)) {
        key = substr(e, 1, RLENGTH); sub(/[ \t]*:$/, "", key)
        val = trim(substr(e, RLENGTH + 1))
      }
    }
    if (key == "" || val == "") continue
    if (key ~ /[\\*]/ || key ~ /\/$/ || key ~ /[ \t]/) continue
    rel = vite_rel(val)
    if (rel == "") continue
    t = norm(joinp(sc, rel))
    if (nbad || t == "") continue
    rel = relto(sc, t)
    if (rel == "") continue
    row(sc, key, rel, 0, 0)
    row(sc, key "/", rel "/", 1, 0)
  }
}

function do_vite(path,   sc, b, s, off, obr, cl, rblk, aopen, acl, arr) {
  sc = dirname(path)
  b = slurp(path, 1)
  if (b == "") return
  s = b; off = 0
  while (match(s, /resolve[ \t]*:[ \t]*\{/)) {
    obr = off + RSTART + RLENGTH - 1
    cl = match_close(b, obr)
    if (cl == 0) return
    rblk = substr(b, obr + 1, cl - obr - 1)
    off = cl
    s = substr(b, cl + 1)
    # An alias that is a variable, a spread or a call has no literal to read.
    if (!match(rblk, /(^|[^A-Za-z0-9_$])alias[ \t]*:[ \t]*[\[{]/)) continue
    aopen = RSTART + RLENGTH - 1
    acl = match_close(rblk, aopen)
    if (acl == 0) continue
    arr = (substr(rblk, aopen, 1) == "[")
    vite_entries(sc, substr(rblk, aopen + 1, acl - aopen - 1), arr)
  }
}

{
  if ($0 == "") next
  if (basename($0) ~ /^vite\.config\./) do_vite($0)
  else do_ts($0)
}
ALIAS_AWK
awk -f "$TMP/aliases-js.awk" < "$TMP/tsconfigs.txt" >> "$TMP/aliases.tsv" 2>/dev/null
# package.json "imports" declares #subpath specifiers, which resolve to real
# files and appear in application code exactly like an alias.
find . -type f -name 'package.json' ! -path '*/node_modules/*' ! -path './.git/*' \
     2>/dev/null | sed 's|^\./||' | head -200 > "$TMP/pkgjsons.txt"
while IFS= read -r PJ; do
  [ -n "$PJ" ] && [ -f "$PJ" ] || continue
  SCOPE="$(dirname "$PJ")"
  [ "$SCOPE" = "." ] && SCOPE=""
  awk -v scope="$SCOPE" '
    { buf = buf " " $0 }
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
        print scope "\t" k "\t" v "\t" wild
      }
    }
  ' "$PJ" >> "$TMP/aliases.tsv" 2>/dev/null
done < "$TMP/pkgjsons.txt"

# composer PSR-4 does the same job for PHP.
if [ -f composer.json ]; then
  awk '
    { buf = buf " " $0 }
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
        print "\t" k "/\t" v "/\t1"
      }
    }
  ' composer.json >> "$TMP/aliases.tsv" 2>/dev/null
fi

: > "$TMP/unresolved.tsv"
# CODE_GRAPH_EXTRA_FILES names a file of paths that are not in the work tree
# any more (blast-radius passes the deleted and renamed-away ones). They join
# the set imports resolve against, so an importer of a deleted file still gets
# its edge, but they are never scanned: src.txt is already fixed above.
if [ -n "${CODE_GRAPH_EXTRA_FILES:-}" ] && [ -f "$CODE_GRAPH_EXTRA_FILES" ]; then
  grep -vxF -f "$TMP/files.txt" "$CODE_GRAPH_EXTRA_FILES" >> "$TMP/files.txt" 2>/dev/null
fi
awk -f "$PLUGIN_ROOT/scripts/code-graph.awk" \
    -v filelist="$TMP/files.txt" \
    -v root="$ROOT" \
    -v gomods="$TMP/gomods.tsv" \
    -v aliases="$TMP/aliases.tsv" \
    -v unresolved="$TMP/unresolved.tsv" \
    < "$TMP/src.txt" > "$TMP/imports.tsv" 2> "$TMP/stats.txt"
AWK_RC=$?
if [ "$AWK_RC" -ne 0 ]; then
  printf 'code-graph: the extractor failed (awk exit %s); the previous graph is untouched\n' "$AWK_RC" >&2
  head -n 5 "$TMP/stats.txt" >&2
  exit 1
fi

# Sorted into scratch files and renamed into place, so a reader never sees a
# half-written graph and a failed sort leaves the previous one in force.
sort -u "$TMP/imports.tsv" > "$TMP/imports.sorted" \
  && sort -u "$TMP/unresolved.tsv" > "$TMP/unresolved.sorted" \
  || { printf 'code-graph: could not sort the graph\n' >&2; exit 1; }
mv -f "$TMP/imports.sorted" "$OUT/imports.tsv" \
  && mv -f "$TMP/unresolved.sorted" "$OUT/unresolved.tsv" \
  || { printf 'code-graph: could not write the graph to %s\n' "$OUT" >&2; exit 1; }

if [ "$QUIET" -eq 0 ]; then
  NE="$(wc -l < "$OUT/imports.tsv" | tr -d ' ')"
  NU="$(wc -l < "$OUT/unresolved.tsv" | tr -d ' ')"
  printf '%s source files, %s import edges, %s unresolved\n' "$NSRC" "$NE" "$NU"
  printf 'wrote %s/imports.tsv\n' "$OUT"
fi
exit 0
