#!/bin/sh
# context-graph - render this project's context layout as a graph you can open.
#
# Usage:
#   context-graph.sh build  [--out DIR] [--root DIR]
#   context-graph.sh serve  [--port N] [--host H] [--no-open]
#   context-graph.sh vault  [--dir DIR]
#   context-graph.sh open
#   context-graph.sh help
#
# POSIX sh and awk. Nothing is installed, nothing is fetched, and the viewer
# it writes is a single self-contained file that opens over file:// with no
# network at all - which is the point on an air-gapped machine.
#
# What it graphs is the context LAYOUT: CLAUDE.md, the tier-2 rules and the
# globs they claim, tier-3 knowledge and skills, commands, agents, findings,
# and the recorded activity over them. Not the code - code structure is in the
# code and an agent can read it.

set -u

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SELF_DIR="."
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/.." 2>/dev/null && pwd)}"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
OUT=""
CMD="${1:-help}"
[ $# -gt 0 ] && shift

PORT=8848
HOST=127.0.0.1
CODE=0
CODECAP=120
VAULT_DIR=""
OPEN_AFTER=1

die() { printf 'context-graph: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --out)   OUT="${2:-}"; shift 2 ;;
    --root)  ROOT="${2:-}"; shift 2 ;;
    --port)  PORT="${2:-}"; shift 2 ;;
    --host)  HOST="${2:-}"; shift 2 ;;
    --dir)   VAULT_DIR="${2:-}"; shift 2 ;;
    --code)  CODE=1; shift ;;
    --code-cap) CODE=1; CODECAP="${2:-120}"; shift 2 ;;
    --no-open) OPEN_AFTER=0; shift ;;
    -h|--help) CMD=help; shift ;;
    *) shift ;;
  esac
done

ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || die "no such directory: $ROOT"
[ -n "$OUT" ] || OUT="$ROOT/.claude/context-graph"
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/context-kit}"
HASH="$(printf '%s' "$ROOT" | cksum 2>/dev/null | cut -d' ' -f1)"
[ -n "$HASH" ] || HASH="default"
EVENTS="$DATA/events/$HASH.tsv"

# --- discovery --------------------------------------------------------------
# Emits "<kind>\t<relative path>" for everything in the layout.
manifest() {
  cd "$ROOT" || return 0
  for f in CLAUDE.md CLAUDE.local.md AGENTS.md .claude/CLAUDE.md; do
    [ -f "$f" ] && printf 'tier1\t%s\n' "$f"
  done
  for d in .claude/rules rules; do
    [ -d "$d" ] || continue
    find "$d" -name '*.md' -type f 2>/dev/null | sed 's|^\./||' | while read -r f; do
      printf 'rule\t%s\n' "$f"
    done
  done
  for d in knowledge .claude/knowledge docs/knowledge; do
    [ -d "$d" ] || continue
    find "$d" -name '*.md' -type f 2>/dev/null | sed 's|^\./||' | while read -r f; do
      printf 'knowledge\t%s\n' "$f"
    done
  done
  for d in .claude/skills skills; do
    [ -d "$d" ] || continue
    find "$d" -name 'SKILL.md' -type f 2>/dev/null | sed 's|^\./||' | while read -r f; do
      printf 'skill\t%s\n' "$f"
    done
  done
  for d in .claude/commands commands; do
    [ -d "$d" ] || continue
    find "$d" -name '*.md' -type f 2>/dev/null | sed 's|^\./||' | while read -r f; do
      printf 'command\t%s\n' "$f"
    done
  done
  for d in .claude/agents agents; do
    [ -d "$d" ] || continue
    find "$d" -name '*.md' -type f 2>/dev/null | sed 's|^\./||' | while read -r f; do
      printf 'agent\t%s\n' "$f"
    done
  done
  for d in findings .claude/findings; do
    [ -d "$d" ] || continue
    find "$d" -name '*.md' -type f 2>/dev/null | sed 's|^\./||' | while read -r f; do
      printf 'finding\t%s\n' "$f"
    done
  done
  for f in .claude/settings.json .claude/settings.local.json hooks/hooks.json .claude/hooks/hooks.json; do
    [ -f "$f" ] && printf 'hook\t%s\n' "$f"
  done
  # Ordinary project docs are scanned as link SOURCES only. They are not a
  # tier and never get one, but a README or an ADR is very often the only
  # thing that points at a knowledge file, and without reading them the
  # reachability finding accuses a well-linked file of being an orphan.
  [ -f README.md ] && printf 'doc\t%s\n' "README.md"
  for d in docs doc adr docs/adr; do
    [ -d "$d" ] || continue
    find "$d" -maxdepth 2 -name '*.md' -type f 2>/dev/null | sed 's|^\./||' | while read -r f; do
      printf 'doc\t%s\n' "$f"
    done
  done
  return 0
}

# Every tracked file in the repo, for resolving a rule's paths: globs against
# reality. git ls-files when this is a work tree - it already honours
# .gitignore, so node_modules never inflates a rule's reach.
repo_files() {
  cd "$ROOT" || return 0
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # --cached AND --others: tracked files only would make a rule's paths:
    # glob under-count a directory of files that are not committed yet, and
    # report a live rule as matching nothing.
    git ls-files --cached --others --exclude-standard 2>/dev/null | sort -u && return 0
  fi
  find . -type f \
    ! -path './.git/*' ! -path './node_modules/*' ! -path './.venv/*' \
    ! -path './venv/*' ! -path './dist/*' ! -path './build/*' \
    ! -path './target/*' ! -path './.claude/context-graph/*' \
    2>/dev/null | sed 's|^\./||'
}

# --- build ------------------------------------------------------------------
do_build() {
  mkdir -p "$OUT" 2>/dev/null || die "cannot create $OUT"
  TMP="$OUT/.tmp.$$"
  mkdir -p "$TMP" 2>/dev/null || die "cannot create $TMP"
  trap 'rm -rf "$TMP" 2>/dev/null' EXIT INT TERM

  repo_files > "$TMP/files.txt" 2>/dev/null
  manifest   > "$TMP/manifest.tsv" 2>/dev/null

  if [ ! -s "$TMP/manifest.tsv" ]; then
    printf 'context-graph: no context layout found under %s.\n' "$ROOT" >&2
    printf '  Looked for CLAUDE.md, .claude/rules/, knowledge/, .claude/skills/,\n' >&2
    printf '  .claude/commands/, .claude/agents/, findings/.\n' >&2
    printf '  Run /context-init first to scaffold one.\n' >&2
    exit 2
  fi

  # The code layer: which module imports which. Built here rather than read
  # from a stale file, because a graph that quietly describes yesterday's
  # imports is worse than no graph.
  IMP=""
  if [ "$CODE" -eq 1 ]; then
    sh "$PLUGIN_ROOT/scripts/code-graph.sh" --root "$ROOT" --out "$OUT" --quiet 2>/dev/null
    [ -s "$OUT/imports.tsv" ] && IMP="$OUT/imports.tsv"
  fi

  EV=""
  [ -r "$EVENTS" ] && EV="$EVENTS"
  STAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
  [ -n "$STAMP" ] || STAMP="unknown"

  awk -f "$PLUGIN_ROOT/scripts/common.awk" -f "$PLUGIN_ROOT/scripts/context-graph.awk" \
      -v root="$ROOT" \
      -v filelist="$TMP/files.txt" \
      -v events="$EV" \
      -v imports="$IMP" \
      -v codecap="$CODECAP" \
      -v generated="$STAMP" \
      < "$TMP/manifest.tsv" > "$TMP/graph.json" || die "graph build failed"

  [ -s "$TMP/graph.json" ] || die "graph build produced nothing"
  mv "$TMP/graph.json" "$OUT/graph.json"

  VIEWER="$PLUGIN_ROOT/templates/graph/viewer.html"
  if [ -r "$VIEWER" ]; then
    # Inline the data rather than fetch it, so the page works over file://
    # with no server and no network. awk, not sed: the payload contains
    # slashes and ampersands that sed would reinterpret.
    awk -v datafile="$OUT/graph.json" '
      /__CONTEXT_GRAPH_DATA__/ {
        while ((getline l < datafile) > 0) {
          # A path or description containing "</script>" would otherwise end
          # the block early and break the page. "<\/" is a legal JSON escape
          # that parses back to "</", so the data survives intact.
          gsub(/<\//, "<\\/", l)
          print l
        }
        close(datafile)
        next
      }
      { print }
    ' "$VIEWER" > "$TMP/graph.html" && mv "$TMP/graph.html" "$OUT/graph.html"
  fi

  rm -rf "$TMP" 2>/dev/null
  trap - EXIT INT TERM

  awk '
    /"stats"/ {
      match($0, /"nodes": [0-9]+/);      n = substr($0, RSTART+9, RLENGTH-9)
      match($0, /"edges": [0-9]+/);      e = substr($0, RSTART+9, RLENGTH-9)
      match($0, /"issues": [0-9]+/);     i = substr($0, RSTART+10, RLENGTH-10)
      match($0, /"tier1_lines": [0-9]+/); t = substr($0, RSTART+15, RLENGTH-15)
      m = ""; if (match($0, /"modules": [0-9]+/)) m = substr($0, RSTART+11, RLENGTH-11)
      h = ""; if (match($0, /"modules_hidden": [0-9]+/)) h = substr($0, RSTART+18, RLENGTH-18)
      printf "%s nodes, %s edges, %s findings, %s lines in tier 1", n, e, i, t
      if (m != "" && m+0 > 0) {
        printf ", %s modules", m
        if (h != "" && h+0 > 0) printf " (%s more not drawn)", h
      }
      printf "\n"
    }
  ' "$OUT/graph.json"
  printf 'wrote %s\n' "$OUT/graph.json"
  [ -f "$OUT/graph.html" ] && printf 'wrote %s\n' "$OUT/graph.html"
  return 0
}

# --- serve ------------------------------------------------------------------
# Rung 4 of the ladder: serve with whatever the machine already ships rather
# than depending on one. Nothing here is installed; if none of them exist the
# page still opens over file://, because the viewer carries its own data.
do_serve() {
  do_build || exit $?
  [ -f "$OUT/graph.html" ] || die "no viewer to serve - templates/graph/viewer.html is missing"

  case "$HOST" in
    127.0.0.1|localhost|::1) : ;;
    *)
      printf 'context-graph: WARNING - binding %s exposes this project'"'"'s context layout\n' "$HOST" >&2
      printf '  (file paths, rule names, skill descriptions, recorded activity) to the\n' >&2
      printf '  network with no authentication. There is no auth here by design; use an\n' >&2
      printf '  SSH tunnel instead if you need remote access.\n' >&2
      ;;
  esac

  URL="http://$HOST:$PORT/graph.html"
  printf 'context-graph: serving %s at %s\n' "$OUT" "$URL"
  printf '  Ctrl-C to stop. The page is self-contained - re-run build to refresh it.\n'

  if command -v python3 >/dev/null 2>&1; then
    exec python3 -m http.server "$PORT" --bind "$HOST" --directory "$OUT"
  elif command -v python >/dev/null 2>&1; then
    cd "$OUT" && exec python -m http.server "$PORT" --bind "$HOST"
  elif command -v php >/dev/null 2>&1; then
    exec php -S "$HOST:$PORT" -t "$OUT"
  elif command -v ruby >/dev/null 2>&1; then
    exec ruby -run -e httpd -- --bind-address="$HOST" --port="$PORT" "$OUT"
  elif command -v busybox >/dev/null 2>&1 && busybox httpd --help 2>&1 | grep -q httpd; then
    exec busybox httpd -f -p "$HOST:$PORT" -h "$OUT"
  else
    printf '\ncontext-graph: no HTTP server on this machine (looked for python3, python,\n' >&2
    printf '  php, ruby, busybox). Nothing to install - the viewer is self-contained,\n' >&2
    printf '  so open it directly:\n\n' >&2
    printf '  file://%s/graph.html\n\n' "$OUT"
    exit 3
  fi
}

do_open() {
  [ -f "$OUT/graph.html" ] || do_build || exit $?
  printf 'file://%s/graph.html\n' "$OUT"
  for opener in xdg-open open wslview; do
    if command -v "$opener" >/dev/null 2>&1; then
      "$opener" "$OUT/graph.html" >/dev/null 2>&1 &
      return 0
    fi
  done
  return 0
}

# --- vault ------------------------------------------------------------------
# One note per node, wikilinked, plus a _MAP.md index. Point --dir at a real
# vault and it stays safe: a manifest records the notes we wrote, and a file
# that is present but not in the manifest is yours and is never overwritten.
# That safety rule is graphify's, learned the hard way when its Obsidian
# export clobbered user notes.
do_vault() {
  do_build >/dev/null || exit $?
  [ -n "$VAULT_DIR" ] || VAULT_DIR="$OUT/vault"
  mkdir -p "$VAULT_DIR" 2>/dev/null || die "cannot create $VAULT_DIR"
  MANIFEST="$VAULT_DIR/.context-kit-vault"

  awk -v vault="$VAULT_DIR" -v manifest="$MANIFEST" -v root="$ROOT" \
      -f "$PLUGIN_ROOT/scripts/context-vault.awk" "$OUT/graph.json"
}

case "$CMD" in
  build) do_build ;;
  serve) do_serve ;;
  vault) do_vault ;;
  open)  do_open ;;
  help|*)
    cat <<'HELP'
context-graph - the context layout as a graph you can open

  build            write .claude/context-graph/graph.json + graph.html
  serve            build, then serve it (loopback only unless --host says otherwise)
  vault            export an Obsidian vault of wikilinked notes
  open             print (and try to open) the file:// URL

  --out DIR        output directory      (default .claude/context-graph)
  --root DIR       project root          (default $CLAUDE_PROJECT_DIR or cwd)
  --port N         serve port            (default 8848)
  --host H         serve bind host       (default 127.0.0.1)
  --dir DIR        vault directory       (default <out>/vault)
  --code           add the module import layer (file-level, from imports)
  --code-cap N     how many modules to draw, by fan-in (default 120)

The viewer is one self-contained file with the data inlined. It needs no
server and no network; serve exists only for when you want a URL.
HELP
    ;;
esac
