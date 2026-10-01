#!/bin/sh
# claude-sections - keep the plugin-owned sections of CLAUDE.md current.
#
# Usage:
#   claude-sections.sh status [FILE] [--level L]   one line per section
#   claude-sections.sh stamp  [FILE] [--level L]   add, update and migrate sections
#   claude-sections.sh off ID [FILE]               turn one section off
#   claude-sections.sh on  ID [FILE] [--level L]   bring it back
#
# FILE defaults to ./CLAUDE.md. L is lite, full or ultra and only matters to the
# lean-execution section; without it the level resolves the way the hooks do.
#
# Each section is one file, templates/sections/NN-<id>.md: NN is its order and
# <id> its name. A stamped section is wrapped in markers, which Claude Code
# strips from CLAUDE.md before loading it, so they cost no tokens:
#
#   <!-- context-kit:begin <id> -->
#   ...body...
#   <!-- context-kit:end <id> -->
#
# A section the user turned off is the single line <!-- context-kit:off <id> -->
# and is never added back by `stamp`.
#
# There are no version numbers. A block is outdated when the text between its
# markers differs from what would be generated now, so the plugin only has to
# change a template and every repo catches up on its next `stamp`. Edits made
# inside the markers are overwritten on purpose; edit the template instead.
#
# The lean-execution body is not a template: it is hooks/rules.md run through
# the same level filter the hooks use, so CLAUDE.md and the injected ruleset
# cannot drift. Level `off` has no ruleset of its own, so it is stamped as full.
#
# 0.4.x wrote the two original sections with no markers. Those are recognised
# by their heading and end line and migrated in place. A block whose end cannot
# be found is reported as legacy-unbounded and never touched: the lean block
# holds `##` subheadings, so "the next heading" cannot bound it.
#
# Content outside the markers is never rewritten. Line endings are normalised
# to LF while working and written back as CRLF when the first line of the file
# ended in CR (a file that mixes the two comes back uniform). Nothing is written
# at all when nothing changed, so a second `stamp` is byte-identical.
#
# Fences are not tracked: a marker or heading inside a code block counts.
#
# Spawning a process costs real time on a managed Windows machine, and the
# session hook calls `status` under a 5 second limit. So the shell only parses
# arguments and builds the wanted section bodies, using builtins, and one awk
# does all the reading, deciding, editing and reporting.

set -u

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SELF_DIR="."
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/.." 2>/dev/null && pwd)}"
SECDIR="$PLUGIN_ROOT/templates/sections"
RULES="$PLUGIN_ROOT/hooks/rules.md"
DATA="${CLAUDE_PLUGIN_DATA:-${HOME:-}/.claude/context-kit}"

die() { printf 'claude-sections: %s\n' "$1" >&2; exit 1; }

CMD="${1:-help}"
[ $# -gt 0 ] && shift

LEVEL_FLAG=""; POS1=""; POS2=""; NPOS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --level)   [ $# -ge 2 ] || die "--level needs a value"; LEVEL_FLAG="$2"; shift 2 ;;
    -h|--help) CMD=help; shift ;;
    --*)       die "unknown option: $1" ;;
    *)
      NPOS=$((NPOS + 1))
      case "$NPOS" in 1) POS1="$1" ;; 2) POS2="$1" ;; *) die "too many arguments" ;; esac
      shift ;;
  esac
done
case "$LEVEL_FLAG" in
  ""|lite|full|ultra|off) : ;;
  *) die "--level must be lite, full, ultra or off" ;;
esac

# --- the sections ----------------------------------------------------------
# The id is the file name without its NN- prefix and .md; the glob sorts by NN.
IDS=""
for f in "$SECDIR"/[0-9][0-9]-*.md; do
  [ -f "$f" ] || continue
  b="${f##*/}"; b="${b#??-}"
  IDS="$IDS ${b%.md}"
done
IDS="${IDS# }"

# Same order as the hooks' resolve_level: the flag, then the environment, then
# the level file, then full. `off` has no ruleset to stamp, so it stamps as full.
resolve_level() {
  L="$LEVEL_FLAG"
  [ -n "$L" ] || L="${CONTEXT_KIT_LEVEL:-}"
  if [ -z "$L" ] && [ -f "$DATA/level" ]; then
    IFS= read -r L < "$DATA/level" || :
    L="${L%"${L##*[![:space:]]}"}"
  fi
  case "$L" in
    lite|full|ultra) LEAN="$L" ;;
    *) LEAN=full ;;
  esac
}

# --- the wanted bodies ------------------------------------------------------
# WANTS holds every section body as it would be stamped now, each introduced by
# an @@<id> line, and goes to awk through the environment. Blank lines are held
# back until something follows them, so a body never ends in one.
WANTS=""; PEND=""

want_start() { WANTS="$WANTS@@$1
"; PEND=""; }

want_line() {
  case "$1" in
    *[![:space:]]*) WANTS="$WANTS$PEND$1
"; PEND="" ;;
    *) PEND="$PEND$1
" ;;
  esac
}

want_template() {
  want_start "$1"
  while IFS= read -r line || [ -n "$line" ]; do
    want_line "${line%"$CR"}"
  done < "$2"
}

# The lean-execution body: what hooks/context-kit.sh ruleset() emits for this
# level, with `# Lean execution` demoted so it nests under CLAUDE.md's own
# headings, and one line telling the orchestrator to pass it to subagents (a
# subagent never reads CLAUDE.md on its own). This is a port of the awk filter
# in ruleset(); scripts/check.sh fails if the two ever disagree.
want_lean() {
  want_start lean-execution
  inc=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%"$CR"}"
    # The leading HTML comment, however many lines it takes.
    case "$line" in "<!--"*) inc=1 ;; esac
    if [ "$inc" -eq 1 ]; then
      case "$line" in *"-->"*) inc=0 ;; esac
      continue
    fi
    case "$line" in
      "["*)
        # [lite] / [full,ultra] prefix: keep the line, minus the prefix, only
        # when it names the current level.
        tag="${line#\[}"; tag="${tag%%\]*}"
        case ",$tag," in
          *",$LEAN,"*)
            rest="${line#\[*\]}"
            want_line "${rest#"${rest%%[![:space:]]*}"}" ;;
        esac ;;
      "# Lean execution"*) want_line "#$line" ;;
      *) want_line "$line" ;;
    esac
  done < "$RULES"
  PEND=""
  want_line ""
  want_line "When spawning a subagent (Task/Agent tool), include this section's content in its prompt."
}

# --- the awk ----------------------------------------------------------------
# Reads FILE once and, by CK_MODE, reports (status) or edits and reports
# (stamp, off, on). Inputs come through the environment: CK_IDS, CK_WANTS,
# CK_ID, CK_CRLF, and CK_FILE for the write-back. Exit status is its verdict.
#
# Blocks are found first: one record per id, as kind and line span.
#   off        <!-- context-kit:off ID --> (every such line is remembered)
#   marked     begin ... end markers for ID
#   unbounded  a block that cannot be bounded safely; never modified
#   legacy     an unmarked 0.4.x block
# An off line beats a block left beside it, and the first of two blocks with
# the same id wins.
AWKPROG='
function marker(t, kind,   w) {
  if (t !~ /^<!-- context-kit:/ || t !~ /-->[ \t]*$/) return ""
  split(t, w, " ")
  return (w[2] == "context-kit:" kind) ? w[3] : ""
}
function trim(e, s) { while (e > s && L[e] ~ /^[ \t]*$/) e--; return e }

function parse_wants(   n, a, i, cur) {
  n = split(ENVIRON["CK_WANTS"], a, "\n")
  for (i = 1; i <= n; i++) {
    if (substr(a[i], 1, 2) == "@@") { cur = substr(a[i], 3); wn[cur] = 0 }
    else if (cur != "") w[cur, ++wn[cur]] = a[i]
  }
  for (cur in wn) while (wn[cur] > 0 && w[cur, wn[cur]] ~ /^[ \t]*$/) wn[cur]--
}

# Does the block at s..e hold exactly the body wanted for id?
function current(id, s, e,   k) {
  if (e - s - 1 != wn[id]) return 0
  for (k = 1; k <= wn[id]; k++) if (L[s + k] != w[id, k]) return 0
  return 1
}

function legacy(id, head,   h, j, e, lim) {
  if (id in kind) return
  for (h = 1; h <= NR; h++) if (!inblk[h] && L[h] ~ ("^" head "[ \t]*$")) break
  if (h > NR) return
  # The scan never crosses another marker: that is someone elses block.
  lim = NR + 1
  for (j = h + 1; j <= NR; j++) if (L[j] ~ /^<!-- context-kit:/) { lim = j; break }
  e = 0
  if (id == "context-layout") {
    # Ends at the line 0.4.x closed the stub with; failing that, before the
    # next heading, so a stub that lost its last line still migrates.
    for (j = h + 1; j < lim; j++) {
      if (index(L[j], "To reorganize any of it, run `/context-init") > 0) { e = j; break }
      if (L[j] ~ /^# / || L[j] ~ /^## /) { e = trim(j - 1, h); break }
    }
    if (!e) e = trim(lim - 1, h)
  } else {
    # The ruleset has ## subheadings, so only its closing lines can end it:
    # the subagent line, else the run of Level lines the filter leaves.
    for (j = h + 1; j < lim; j++)
      if (index(L[j], "When spawning a subagent (Task/Agent tool)") == 1) { e = j; break }
    if (!e) {
      for (j = h + 1; j < lim; j++) if (L[j] ~ /^Level (lite|full|ultra):/) break
      if (j < lim) { e = j; while (e + 1 < lim && L[e + 1] ~ /^Level (lite|full|ultra):/) e++ }
    }
    if (!e) { kind[id] = "unbounded"; ks[id] = h; ke[id] = h; return }
  }
  kind[id] = "legacy"; ks[id] = h; ke[id] = e
}

function locate(   i, j, k, id) {
  for (i = 1; i <= NR; i++) {
    id = marker(L[i], "off")
    if (id == "") continue
    if (!(id in kind)) { kind[id] = "off"; ks[id] = i; ke[id] = i }
    if (kind[id] == "off") offl[id, ++noff[id]] = i
  }
  for (i = 1; i <= NR; i++) {
    id = marker(L[i], "begin")
    if (id == "") continue
    for (j = i + 1; j <= NR; j++) if (marker(L[j], "end") == id) break
    if (j > NR) {
      if (!(id in kind)) { kind[id] = "unbounded"; ks[id] = i; ke[id] = i }
      continue
    }
    for (k = i; k <= j; k++) inblk[k] = 1
    if (!(id in kind)) { kind[id] = "marked"; ks[id] = i; ke[id] = j }
    i = j
  }
  legacy("context-layout", "## Context layout")
  legacy("lean-execution", "## Lean execution")
}

function word(id) {
  if (!(id in kind)) return "missing"
  if (kind[id] == "off") return "off"
  if (kind[id] == "legacy") return "legacy"
  if (kind[id] == "unbounded") return "legacy-unbounded"
  return current(id, ks[id], ke[id]) ? "ok" : "outdated"
}

function say(s) { msgs[++nm] = s }
function warn(s) { print "claude-sections: " s > "/dev/stderr" }
function replace(s, e, how, id) { rk[s] = how; re[s] = e; ri[s] = id; changed = 1 }
function append(how, id) { app[++napp] = how SUBSEP id; changed = 1 }

# Bring one section up to date. Returns what it did, or "" for nothing.
function stamp_one(id) {
  if (!(id in kind)) { append("block", id); return "added" }
  if (kind[id] == "marked") {
    if (current(id, ks[id], ke[id])) return ""
    replace(ks[id] + 1, ke[id] - 1, "body", id)
    return "updated"
  }
  if (kind[id] == "legacy") { replace(ks[id], ke[id], "block", id); return "migrated" }
  if (kind[id] == "unbounded")
    warn(id " is an unmarked block with no recognizable end; left untouched")
  return ""
}

function emit_repl(s,   id, k, how) {
  id = ri[s]; how = rk[s]
  if (how == "off") { out[++n] = "<!-- context-kit:off " id " -->"; return }
  if (how == "del") return
  if (how == "block") out[++n] = "<!-- context-kit:begin " id " -->"
  for (k = 1; k <= wn[id]; k++) out[++n] = w[id, k]
  if (how == "block") out[++n] = "<!-- context-kit:end " id " -->"
}

BEGIN {
  mode = ENVIRON["CK_MODE"]; tid = ENVIRON["CK_ID"]
  eol = (ENVIRON["CK_CRLF"] == "1") ? "\r" : ""
  nids = split(ENVIRON["CK_IDS"], ids, " ")
  parse_wants()
}
{ sub(/\r$/, ""); L[NR] = $0 }
END {
  locate()

  if (mode == "status") {
    for (i = 1; i <= nids; i++) print word(ids[i]), ids[i]
    exit 0
  }

  if (mode == "stamp") {
    for (i = 1; i <= nids; i++) {
      act = stamp_one(ids[i])
      if (act != "") say("stamped " ids[i] " (" act ")")
    }
  } else if (mode == "off") {
    if (!(tid in kind))            { append("off", tid); say("off " tid) }
    else if (kind[tid] == "off")   say("off " tid " (unchanged)")
    else if (kind[tid] == "unbounded") {
      print "claude-sections: cannot turn off " tid ": its block has no recognizable end, so remove it by hand" > "/dev/stderr"
      exit 1
    } else { replace(ks[tid], ke[tid], "off", tid); say("off " tid) }
  } else if (mode == "on") {
    if ((tid in kind) && kind[tid] == "off") {
      # Back where it was, not at the end of the file; any second off line goes.
      replace(ks[tid], ke[tid], "block", tid)
      for (k = 2; k <= noff[tid]; k++) replace(offl[tid, k], offl[tid, k], "del", tid)
      say("on " tid)
    } else {
      act = stamp_one(tid)
      say("on " tid (act != "" ? " (" act ")" : " (unchanged)"))
    }
  } else exit 1

  if (changed) {
    i = 1
    while (i <= NR) {
      if (i in rk) {
        emit_repl(i)
        if (re[i] >= i) { i = re[i] + 1; continue }
      }
      out[++n] = L[i]; i++
    }
    # Appended blocks are each set off by one blank line.
    for (k = 1; k <= napp; k++) {
      split(app[k], a, SUBSEP)
      if (n > 0 && out[n] !~ /^[ \t]*$/) out[++n] = ""
      if (a[1] == "off") out[++n] = "<!-- context-kit:off " a[2] " -->"
      else { rk[0] = "block"; ri[0] = a[2]; emit_repl(0) }
    }
    f = ENVIRON["CK_FILE"]
    for (i = 1; i <= n; i++) print out[i] eol > f
    close(f)
  } else n = NR

  for (i = 1; i <= nm; i++) print msgs[i]
  printf "CLAUDE.md: %d lines%s\n", n, (n > 200 ? " (over the 200-line cap — run /context-init cleanup)" : "")
}
'

run() {  # $1 mode
  CK_MODE="$1" CK_ID="${ID:-}" CK_IDS="$IDS" CK_WANTS="$WANTS" CK_CRLF="$CRLF" \
    CK_FILE="$FILE" awk "$AWKPROG" "$INPUT"
}

prepare() {
  [ -n "$IDS" ] || die "no section templates in $SECDIR"
  CR="$(printf '\r')"
  CRLF=0; INPUT=/dev/null
  if [ -f "$FILE" ]; then
    INPUT="$FILE"
    IFS= read -r first < "$FILE" || :
    case "$first" in *"$CR") CRLF=1 ;; esac
  fi
  resolve_level
  for id in $IDS; do
    if [ "$id" = lean-execution ]; then
      [ -r "$RULES" ] || die "cannot read $RULES"
      want_lean
    else
      set -- "$SECDIR"/[0-9][0-9]-"$id".md
      want_template "$id" "$1"
    fi
  done
}

need_id() {
  [ -n "$ID" ] || die "$CMD needs a section id"
  case " $IDS " in *" $ID "*) : ;; *) die "unknown section '$ID' (known: $IDS)" ;; esac
}

usage() {
  cat <<'HELP'
claude-sections - keep the plugin-owned sections of CLAUDE.md current

  status [FILE]   one line per section: ok, missing, outdated, off, legacy
                  or legacy-unbounded
  stamp  [FILE]   add missing sections at the end, rewrite outdated ones in
                  place, wrap 0.4.x blocks in markers, leave off sections alone
  off ID [FILE]   replace a section with <!-- context-kit:off ID -->
  on  ID [FILE]   put it back
  --level L       lite, full or ultra: the level the lean-execution section is
                  stamped at (default: the hooks' level)

FILE defaults to ./CLAUDE.md. `stamp` needs the file to exist. Sections live
in templates/sections/; edits inside a stamped block are overwritten.
HELP
}

case "$CMD" in
  status)
    [ -z "$POS2" ] || die "status takes one file"
    FILE="${POS1:-./CLAUDE.md}"
    prepare
    run status ;;
  stamp)
    [ -z "$POS2" ] || die "stamp takes one file"
    FILE="${POS1:-./CLAUDE.md}"
    [ -f "$FILE" ] || die "no such file: $FILE (create it with a title line first)"
    prepare
    run stamp ;;
  off|on)
    ID="$POS1"
    FILE="${POS2:-./CLAUDE.md}"
    [ -n "$IDS" ] || die "no section templates in $SECDIR"
    need_id
    [ -f "$FILE" ] || die "no such file: $FILE"
    prepare
    run "$CMD" ;;
  help) usage ;;
  *) die "unknown command '$CMD' (status, stamp, off, on)" ;;
esac
