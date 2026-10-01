#!/bin/sh
# context-sync - find the project markdown and the layout gaps that need routing.
#
# Usage (run from the project root):
#   context-sync.sh check                   one line per thing that needs work;
#                                           nothing at all when all is current
#   context-sync.sh diff PATH               what changed in PATH since it was last marked
#   context-sync.sh mark PATH... | --all    record PATH (or everything `check` reports
#                                           as a source or a finding) as synced
#   context-sync.sh sources add GLOB        also treat files matching GLOB as sources
#   context-sync.sh sources list            the globs in force
#   context-sync.sh help
#
# Project markdown (PROGRESS.md, docs/, notes, ideas) is the source. knowledge/,
# findings/, .claude/rules/ and .claude/skills/ are where it is routed so that it
# loads when it is needed. This script only reports and records; it never writes
# to those folders and never calls a model. The context-sync skill does the
# routing, from the lines `check` prints.
#
# The ledger, .claude/context-sync.tsv, is committed so a team shares its sync
# state. Rows are tab-separated:
#
#   kind  path  blob  commit  date
#
# kind is `source` or `findings`; blob is `git hash-object` of the file when it
# was marked; commit is HEAD at that moment (`-` before the first commit); date
# is YYYY-MM-DD, UTC. The first line, when there is one, is `#sources`, a tab,
# and the extra source globs `sources add` persists, separated by spaces. Rows
# are sorted, so two people marking different files rarely collide in git.
#
# Sources are the markdown files at the repo root and under docs/, tracked or
# untracked-but-not-ignored (one `git ls-files`), plus the header globs, minus
# CLAUDE.md and CLAUDE.local.md, knowledge/, findings/, .claude/, .github/, and
# any node_modules, vendor, dist or build directory. A glob is a shell case
# pattern: `*` matches anything, `/` included, so docs/**/*.md and docs/*.md
# are the same glob, and a glob holds no spaces.
#
# `check` lines, in this order. Nothing else is ever printed, and the exit
# status is 0 whether or not there was anything to say:
#   layout missing                  none of the four folders exists; nothing else is printed
#   source new|changed|gone PATH    a source never marked, edited since, or removed since
#   findings changed PATH           a findings/ log never marked or appended to since
#   findings lessons-stale          LESSONS.md is older than an entry (findings.sh decides)
#   index missing PATH              a knowledge file or project skill with no row in
#                                   knowledge/INDEX.md
#   rule no-paths PATH              a .claude/rules/ file with no `paths:` frontmatter
#   skill no-trigger PATH           a project skill whose description is not a trigger
#   sections STATE ID               a managed CLAUDE.md section that is not ok or off
#
# The project root is the working directory, not CLAUDE_PROJECT_DIR, so a git
# worktree syncs itself. `mark` records what is on disk when it runs: a file
# edited between `check` and `mark` is recorded as if it had been routed.
#
# `check` runs at the start of every session, and on a managed Windows machine
# starting a process costs a few hundred milliseconds and forking a subshell
# about a hundred. So it spends one `git ls-files` and one batched
# `git hash-object`, compares hashes instead of reading files, does its
# filtering and option parsing in shell builtins, and runs the checks that
# call other scripts (findings.sh, claude-sections.sh) beside the git work
# rather than after it.

set -u

die() { printf 'context-sync: %s\n' "$1" >&2; exit 1; }

# The plugin root, found without forking: cd is a builtin, `$(cd ... && pwd)`
# is not.
START="$PWD"
case "$0" in */*) SELF_DIR="${0%/*}" ;; *) SELF_DIR="." ;; esac
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  PLUGIN_ROOT="$SELF_DIR/.."
  cd "$SELF_DIR/.." 2>/dev/null && PLUGIN_ROOT="$PWD"
  cd "$START" || exit 1
fi
ROOT="$START"
LEDGER=".claude/context-sync.tsv"

CMD="${1:-help}"
[ $# -gt 0 ] && shift

# Options are lifted out of the argument list; what is left stays in "$@".
ALL=0
n=$#
while [ "$n" -gt 0 ]; do
  a="$1"; shift; n=$((n - 1))
  case "$a" in
    --all)     ALL=1 ;;
    --root)    [ "$n" -gt 0 ] || die "--root needs a directory"; ROOT="$1"; shift; n=$((n - 1)) ;;
    -h|--help) CMD=help ;;
    *)         set -- "$@" "$a" ;;
  esac
done

# --- the awk programs --------------------------------------------------------
# Held in variables so one definition of the sort serves them all. No
# apostrophes inside them: they live in single quotes.

# Byte-order sort in awk: a locale-dependent `sort` would reorder the committed
# ledger between machines.
ISORT_AWK='
function isort(a, n,   gap, i, j, t) {
  for (gap = int(n / 2); gap > 0; gap = int(gap / 2))
    for (i = gap + 1; i <= n; i++) {
      t = a[i]
      for (j = i; j > gap && a[j - gap] > t; j -= gap) a[j] = a[j - gap]
      a[j] = t
    }
}
'

# Ledger, hashes and paths -> the source and findings lines. The hash file and
# the path file are the same length and in the same order.
CLASSIFY_AWK='
BEGIN { FS = "\t" }
FILENAME == F_LEDGER {
  sub(/\r$/, "")
  if ($1 == "source" || $1 == "findings") { lb[$2] = $3; lk[$2] = $1 }
  next
}
FILENAME == F_HASH { if ($0 != "") hs[++nh] = $0; next }
FILENAME == F_PATH { if ($0 != "") ps[++nq] = $0; next }
END {
  for (i = 1; i <= nq; i++) {
    p = ps[i]
    if (p in cur) continue
    cur[p] = 1
    k = (p ~ /^findings\//) ? "findings" : "source"
    if (!(p in lb)) st = "new"
    else if (lb[p] != hs[i]) st = "changed"
    else continue
    if (k == "findings") st = "changed"
    out[++n] = k " " st " " p
  }
  # A findings file that vanished is not worth a line; the next write drops its row.
  for (p in lb) if (!(p in cur) && lk[p] == "source") out[++n] = "source gone " p
  isort(out, n)
  for (i = 1; i <= n; i++) print out[i]
}
'

# The manifest of knowledge files (K), project skills (S) and rules (R) ->
# the index, rule and skill lines. Files are read here with getline.
LINT_AWK='
function mentions(text, needle,   off, pos, bef, aft) {
  off = 0
  while ((pos = index(substr(text, off + 1), needle)) > 0) {
    bef = (off + pos > 1) ? substr(text, off + pos - 1, 1) : ""
    aft = substr(text, off + pos + length(needle), 1)
    if (bef !~ /[A-Za-z0-9_-]/ && aft !~ /[A-Za-z0-9_-]/) return 1
    off += pos
  }
  return 0
}
function load_fm(f,   line, first) {
  fmn = 0; first = 1
  while ((getline line < f) > 0) {
    sub(/\r$/, "", line)
    if (first) { first = 0; if (line !~ /^---[ \t]*$/) break; continue }
    if (line ~ /^---[ \t]*$/) break
    fm[++fmn] = line
  }
  close(f)
}
function has_paths(   i, j, v) {
  for (i = 1; i <= fmn; i++) {
    if (fm[i] !~ /^paths[ \t]*:/) continue
    v = fm[i]; sub(/^paths[ \t]*:[ \t]*/, "", v)
    if (v != "" && v !~ /^(\[\]|"")[ \t]*$/) return 1
    for (j = i + 1; j <= fmn; j++) {
      if (fm[j] ~ /^[ \t]*$/) continue
      return (fm[j] ~ /^[ \t]*-[ \t]*[^ \t]/) ? 1 : 0
    }
    return 0
  }
  return 0
}
function description(   i, d, on) {
  d = ""; on = 0
  for (i = 1; i <= fmn; i++) {
    if (!on) { if (fm[i] ~ /^description[ \t]*:/) { on = 1; d = fm[i] }; continue }
    if (fm[i] ~ /^[A-Za-z_-]+[ \t]*:/) break
    d = d " " fm[i]
  }
  return d
}
BEGIN {
  FS = "\t"
  f = "knowledge/INDEX.md"
  while ((getline line < f) > 0) { sub(/\r$/, "", line); idx = idx line "\n" }
  close(f)
}
$1 == "K" {
  name = $2; sub(/^knowledge\//, "", name)
  if (!mentions(idx, name)) io[++ni] = "index missing " $2
  next
}
$1 == "S" {
  split($2, seg, "/"); nm = seg[3]
  if (!mentions(idx, "skills/" nm) && index(idx, "`" nm "`") == 0) io[++ni] = "index missing " $2
  load_fm($2)
  if (description() !~ /Use when|use when|Use immediately/) so[++ns] = "skill no-trigger " $2
  next
}
$1 == "R" {
  load_fm($2)
  if (!has_paths()) ro[++nr] = "rule no-paths " $2
}
END {
  for (i = 1; i <= ni; i++) print io[i]
  for (i = 1; i <= nr; i++) print ro[i]
  for (i = 1; i <= ns; i++) print so[i]
}
'

# Ledger, hashes, paths and marks -> the rewritten ledger. `mark` upserts each
# marked path from the current state, or drops its row when the file is gone;
# `sources` adds a glob to the header. Either way findings rows for vanished
# files are dropped.
LEDGER_AWK='
BEGIN {
  FS = "\t"
  mode = ENVIRON["CK_MODE"]; head = ENVIRON["CK_HEAD"]
  day = ENVIRON["CK_DATE"]; glob = ENVIRON["CK_GLOB"]
}
FILENAME == F_LEDGER {
  sub(/\r$/, "")
  if ($1 == "#sources") {
    ng0 = split($2, ga, " ")
    for (i = 1; i <= ng0; i++) if (!(ga[i] in gs)) { gs[ga[i]] = 1; globs[++ng] = ga[i] }
  } else if ($1 == "source" || $1 == "findings") {
    k[$2] = $1; b[$2] = $3; c[$2] = $4; d[$2] = $5
  }
  next
}
FILENAME == F_HASH { if ($0 != "") hs[++nh] = $0; next }
FILENAME == F_PATH { if ($0 != "") ps[++nq] = $0; next }
FILENAME == F_MARKS { if ($0 != "") want[$0] = 1; next }
END {
  for (i = 1; i <= nq; i++) sb[ps[i]] = hs[i]
  if (mode == "sources") {
    if (!(glob in gs)) { gs[glob] = 1; globs[++ng] = glob }
  } else {
    for (p in want) {
      if (p in sb) {
        k[p] = (p ~ /^findings\//) ? "findings" : "source"
        b[p] = sb[p]; c[p] = head; d[p] = day
      } else if (p in k) {
        delete k[p]; delete b[p]; delete c[p]; delete d[p]
      } else print "context-sync: " p " is not a source or a findings log; ignored" > "/dev/stderr"
    }
  }
  for (p in k) {
    if (mode != "sources" && k[p] == "findings" && !(p in sb)) continue
    rows[++nr] = k[p] "\t" p "\t" b[p] "\t" c[p] "\t" d[p]
  }
  isort(rows, nr)
  if (ng > 0) {
    line = "#sources\t" globs[1]
    for (i = 2; i <= ng; i++) line = line " " globs[i]
    print line
  }
  for (i = 1; i <= nr; i++) print rows[i]
}
'

# --- helpers ------------------------------------------------------------------
# Scratch files are redirects, which cost nothing; a command substitution
# forks. They are removed in the background on the way out, so the caller does
# not wait for an rm.
T="${TMPDIR:-/tmp}/context-sync.$$"
use_tmp() {
  trap 'rm -f "$T".* >/dev/null 2>&1 &' EXIT
  trap 'exit 1' HUP INT TERM
}

# A path as the ledger spells it: forward slashes, no leading ./, relative to
# the root.
norm() {
  p="$1"
  case "$p" in *\\*) p="$(printf '%s' "$p" | tr '\\' '/')" ;; esac
  case "$p" in "$ROOT"/*) p="${p#"$ROOT"/}" ;; esac
  while :; do
    case "$p" in ./*) p="${p#./}" ;; *) break ;; esac
  done
  printf '%s' "$p"
}

# $LEDGER_IN is the ledger, or /dev/null so awk always has a file to read.
# $EXTRAS is the header globs, space separated, with any CR from a CRLF
# checkout cut off.
ledger_in() {
  LEDGER_IN="$LEDGER"; EXTRAS=""
  if [ ! -f "$LEDGER" ]; then LEDGER_IN=/dev/null; return 0; fi
  first=""
  IFS= read -r first < "$LEDGER" || :
  case "$first" in
    "#sources"*)
      set -f
      for g in ${first#"#sources"}; do
        g="${g%%[[:cntrl:]]*}"
        [ -n "$g" ] && EXTRAS="$EXTRAS $g"
      done
      set +f ;;
  esac
}

# Is $1 a source path? Markdown at the root, anything .md under docs/, or a
# match for one of the header globs; and not one of the excluded places.
is_source() {
  case "$1" in
    CLAUDE.md|CLAUDE.local.md|*/CLAUDE.md|*/CLAUDE.local.md) return 1 ;;
    knowledge/*|findings/*|.claude/*|.github/*) return 1 ;;
    node_modules/*|*/node_modules/*|vendor/*|*/vendor/*) return 1 ;;
    dist/*|*/dist/*|build/*|*/build/*) return 1 ;;
  esac
  case "$1" in
    */*) : ;;
    *.md) return 0 ;;
  esac
  case "$1" in docs/*.md) return 0 ;; esac
  for g in $EXTRAS; do
    case "$1" in $g) return 0 ;; esac
  done
  return 1
}

# $T.paths and $T.hash: every source and every findings log as it is now, one
# per line, and its blob hash on the same line number of the other file.
build_state() {
  ledger_in
  set -f
  set -- '*.md'
  for g in $EXTRAS; do set -- "$@" "$g"; done
  if ! git -c core.quotepath=false ls-files --cached --others --exclude-standard -- "$@" \
        > "$T.ls" 2>/dev/null; then
    # Not a git work tree: walk the files instead.
    find . \( -name .git -o -name node_modules \) -prune -o -type f -name '*.md' -print \
      2>/dev/null | sed 's|^\./||' > "$T.ls"
  fi

  # ls-files also lists a file deleted from the work tree while it is still in
  # the index, and hash-object cannot read it.
  : > "$T.paths"
  while IFS= read -r p; do
    if is_source "$p" && [ -f "$p" ]; then printf '%s\n' "$p"; fi
  done < "$T.ls" >> "$T.paths"
  set +f

  # The findings logs. LESSONS.md is generated; README.md is the convention.
  for f in findings/*.md; do
    [ -f "$f" ] || continue
    case "$f" in findings/README.md|findings/LESSONS.md) continue ;; esac
    printf '%s\n' "$f" >> "$T.paths"
  done

  if ! git hash-object --stdin-paths < "$T.paths" > "$T.hash" 2>/dev/null; then
    # One unreadable file fails the whole batch; go one at a time, drop it.
    : > "$T.hash"; : > "$T.ok"
    while IFS= read -r p; do
      h="$(git hash-object -- "$p" 2>/dev/null)" || continue
      printf '%s\n' "$h" >> "$T.hash"
      printf '%s\n' "$p" >> "$T.ok"
    done < "$T.paths"
    cat "$T.ok" > "$T.paths"
  fi
}

# Print a file's lines, without forking a cat.
emit() {
  [ -s "$1" ] || return 0
  while IFS= read -r l; do printf '%s\n' "$l"; done < "$1"
}

# index, rule and skill lines.
lint() {
  {
    for f in knowledge/*.md; do
      [ -f "$f" ] || continue
      [ "$f" = knowledge/INDEX.md ] && continue
      printf 'K\t%s\n' "$f"
    done
    for f in .claude/skills/*/SKILL.md; do
      [ -f "$f" ] && printf 'S\t%s\n' "$f"
    done
    for f in .claude/rules/*.md; do
      [ -f "$f" ] && printf 'R\t%s\n' "$f"
    done
  } > "$T.manifest"
  [ -s "$T.manifest" ] || return 0
  awk "$LINT_AWK" "$T.manifest"
}

# findings.sh owns the rule for a stale LESSONS.md; ask it rather than copy it.
# It only counts when there is a log to be stale about.
lessons() {
  has=0
  for f in findings/*.md; do
    [ -f "$f" ] || continue
    case "$f" in findings/README.md|findings/LESSONS.md) continue ;; esac
    has=1; break
  done
  [ "$has" -eq 1 ] || return 0
  [ -f "$PLUGIN_ROOT/scripts/findings.sh" ] || return 0
  sh "$PLUGIN_ROOT/scripts/findings.sh" reflect --check --root "$ROOT" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 3 ]; then printf 'findings lessons-stale\n'; fi
}

# Every managed CLAUDE.md section that is neither current nor deliberately off.
sections() {
  [ -f CLAUDE.md ] || return 0
  [ -f "$PLUGIN_ROOT/scripts/claude-sections.sh" ] || return 0
  sh "$PLUGIN_ROOT/scripts/claude-sections.sh" status CLAUDE.md > "$T.status" 2>/dev/null
  while read -r st id _; do
    case "$st" in ok|off|"") : ;; *) printf 'sections %s %s\n' "$st" "$id" ;; esac
  done < "$T.status"
}

# Rewrite the ledger through LEDGER_AWK. $1 is the mode, mark or sources; the
# state files and the marks file may not exist yet.
write_ledger() {
  mkdir -p .claude 2>/dev/null || die "cannot create .claude"
  ledger_in
  for f in paths hash marks; do [ -f "$T.$f" ] || : > "$T.$f"; done
  HEAD_REV="$(git rev-parse --verify -q HEAD 2>/dev/null)"
  [ -n "$HEAD_REV" ] || HEAD_REV="-"
  NEWL="$LEDGER.tmp.$$"
  CK_MODE="$1" CK_HEAD="$HEAD_REV" CK_DATE="$(date -u '+%Y-%m-%d' 2>/dev/null)" CK_GLOB="${GLOB:-}" \
    awk -v F_LEDGER="$LEDGER_IN" -v F_HASH="$T.hash" -v F_PATH="$T.paths" -v F_MARKS="$T.marks" \
      "$ISORT_AWK$LEDGER_AWK" "$LEDGER_IN" "$T.hash" "$T.paths" "$T.marks" > "$NEWL" \
    || { rm -f "$NEWL"; die "cannot update $LEDGER"; }
  mv "$NEWL" "$LEDGER" || { rm -f "$NEWL"; die "cannot write $LEDGER"; }
}

# --- commands -----------------------------------------------------------------
do_check() {
  if [ ! -d knowledge ] && [ ! -d findings ] && [ ! -d .claude/rules ] && [ ! -d .claude/skills ]; then
    printf 'layout missing\n'
    return 0
  fi
  use_tmp
  # The checks that start other scripts take longest, so they start first and
  # run beside the git work.
  lessons > "$T.lessons" 2>/dev/null &
  sections > "$T.sections" 2>/dev/null &
  lint > "$T.lint" 2>/dev/null &
  build_state
  awk -v F_LEDGER="$LEDGER_IN" -v F_HASH="$T.hash" -v F_PATH="$T.paths" \
    "$ISORT_AWK$CLASSIFY_AWK" "$LEDGER_IN" "$T.hash" "$T.paths" > "$T.items"
  wait
  emit "$T.items"
  emit "$T.lessons"
  emit "$T.lint"
  emit "$T.sections"
  return 0
}

do_diff() {
  [ $# -eq 1 ] || die "diff needs one PATH"
  p="$(norm "$1")"
  TAB="$(printf '\t')"
  have=0; oldblob=""; oldcommit=""
  if [ -f "$LEDGER" ]; then
    while IFS="$TAB" read -r k rp rb rc _; do
      case "$k" in
        source|findings)
          if [ "$rp" = "$p" ]; then have=1; oldblob="$rb"; oldcommit="$rc"; break; fi ;;
      esac
    done < "$LEDGER"
  fi

  if [ ! -f "$p" ]; then
    [ "$have" -eq 1 ] || die "no such file: $p"
    printf '# context-sync: %s was removed since the last sync\n' "$p"
    return 0
  fi
  if [ "$have" -eq 0 ]; then
    printf '# context-sync: %s has never been synced; the whole file follows\n' "$p"
    cat -- "$p"
    return 0
  fi
  cur="$(git hash-object -- "$p" 2>/dev/null)"
  if [ "$cur" = "$oldblob" ]; then
    printf '# context-sync: %s is unchanged since the last sync\n' "$p"
    return 0
  fi

  oldcommit="${oldcommit%%[[:cntrl:]]*}"
  if [ -z "$oldcommit" ] || [ "$oldcommit" = "-" ]; then
    reason="there was no commit at the last sync"
  elif ! git cat-file -e "$oldcommit:$p" 2>/dev/null; then
    reason="it was not in git at the last sync ($oldcommit)"
  else
    # No context lines, and the hunk headers cut back to their ranges (git
    # appends the nearest earlier line to them): this shows only what is new,
    # and the router can open the file when it needs the surroundings.
    d="$(git diff --no-color --no-ext-diff --unified=0 "$oldcommit" -- "$p" 2>/dev/null \
         | sed 's/^\(@@[^@]*@@\).*$/\1/')"
    if [ -n "$d" ]; then printf '%s\n' "$d"; return 0; fi
    reason="git shows no difference from $oldcommit although the content changed"
  fi
  printf '# context-sync: %s: %s; the whole file follows\n' "$p" "$reason"
  cat -- "$p"
}

do_mark() {
  use_tmp
  : > "$T.marks"
  if [ "$ALL" -eq 1 ]; then
    build_state
    awk -v F_LEDGER="$LEDGER_IN" -v F_HASH="$T.hash" -v F_PATH="$T.paths" \
      "$ISORT_AWK$CLASSIFY_AWK" "$LEDGER_IN" "$T.hash" "$T.paths" > "$T.items"
    # The path is everything after the first two words; gone paths are included
    # so that their rows are dropped.
    awk '($1 == "source" || $1 == "findings") && ($2 == "new" || $2 == "changed" || $2 == "gone") {
           sub(/^[^ ]+ [^ ]+ /, ""); print }' "$T.items" > "$T.marks"
  else
    [ $# -gt 0 ] || die "mark needs PATH... or --all"
    for a in "$@"; do printf '%s\n' "$(norm "$a")" >> "$T.marks"; done
    build_state
  fi
  write_ledger mark
  printf 'marked %s path(s) in %s\n' "$(grep -c . "$T.marks")" "$LEDGER"
}

do_sources() {
  sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    list)
      printf 'default *.md\ndefault docs/**/*.md\n'
      ledger_in
      set -f
      for g in $EXTRAS; do printf 'extra %s\n' "$g"; done
      set +f ;;
    add)
      [ $# -eq 1 ] || die "sources add needs one GLOB"
      GLOB="$1"
      case "$GLOB" in
        ""|/*|*[[:space:]]*|*..*) die "not a usable glob: '$GLOB' (relative to the root, no spaces, no '..')" ;;
      esac
      ledger_in
      set -f
      for g in '*.md' 'docs/**/*.md' $EXTRAS; do
        if [ "$g" = "$GLOB" ]; then
          set +f
          printf 'already a source glob: %s\n' "$GLOB"
          return 0
        fi
      done
      set +f
      use_tmp
      write_ledger sources
      printf 'added source glob: %s\n' "$GLOB" ;;
    *) die "sources takes 'add GLOB' or 'list'" ;;
  esac
}

usage() {
  cat <<'HELP'
context-sync - find project markdown and layout gaps that need routing

  check          one line per item that needs work, nothing when all is current:
                   layout missing
                   source new|changed|gone PATH
                   findings changed PATH | findings lessons-stale
                   index missing PATH | rule no-paths PATH | skill no-trigger PATH
                   sections STATE ID
  diff PATH      what changed in PATH since it was last marked (git diff from
                 the ledger commit; the whole file when it is new)
  mark PATH...   record each PATH as synced; a PATH that is gone drops its row
  mark --all     mark everything `check` reports as a source or a finding
  sources add GLOB | list
                 extra source globs, kept in .claude/context-sync.tsv

Sources are root *.md and docs/**/*.md, tracked or untracked-but-not-ignored.
The ledger .claude/context-sync.tsv is committed. --root DIR runs elsewhere.
HELP
}

cd "$ROOT" 2>/dev/null || die "no such directory: $ROOT"
ROOT="$PWD"
command -v git >/dev/null 2>&1 || die "git is required"

case "$CMD" in
  check)   do_check ;;
  diff)    do_diff "$@" ;;
  mark)    do_mark "$@" ;;
  sources) do_sources "$@" ;;
  help)    usage ;;
  *)       die "unknown command '$CMD' (check, diff, mark, sources, help)" ;;
esac
