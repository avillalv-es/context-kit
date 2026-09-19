#!/bin/sh
# context-kit hook entrypoint. POSIX sh, no external runtime.
#
# Usage: context-kit.sh session|subagent|mode|signal
#
# Fails open, always. Every error path exits 0 with no output: a broken hook
# must never block a session. Hook engineering patterns (fail-open, once-only
# nudges, whole-message deactivation, hardcoded fallback) are adapted from
# ponytail (MIT, Dietrich Gebert). See NOTICE.

ACTION="${1:-}"

# --- escape hatches, read before anything else ----------------------------
[ "${CONTEXT_KIT_OFF:-}" = "1" ] && exit 0

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$ROOT" ] || ROOT="$(dirname "$0")/.."
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/context-kit}"
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
RULES="$ROOT/hooks/rules.md"
NATIVE="$ROOT/knowledge/platform-native.md"
THRESHOLD=3

# Reject paths unsafe to hand to a shell. Ponytail isShellSafe.
is_safe() {
  case "$1" in
    *[!A-Za-z0-9\ _.:/~-]*) return 1 ;;
    *) return 0 ;;
  esac
}
is_safe "$DATA" || DATA="$HOME/.claude/context-kit"

HASH="$(printf '%s' "$PROJ" | cksum 2>/dev/null | cut -d' ' -f1)"
[ -n "$HASH" ] || HASH="default"

# --- level ----------------------------------------------------------------
resolve_level() {
  L="${CONTEXT_KIT_LEVEL:-}"
  if [ -z "$L" ] && [ -f "$DATA/level" ]; then
    L="$(head -1 "$DATA/level" 2>/dev/null)"
  fi
  case "$L" in
    lite|full|ultra|off) printf '%s' "$L" ;;
    *) printf 'full' ;;
  esac
}

# --- JSON helpers ---------------------------------------------------------
json_escape() {
  awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,""); print $0 "\\n"}'
}

emit() {
  # $1 = hookEventName; context text on stdin
  ESCAPED="$(json_escape)"
  [ -z "$ESCAPED" ] && exit 0
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$ESCAPED"
}

# Extract a flat string field from stdin JSON without jq. Best effort: a miss
# yields an empty string, which every caller treats as "skip".
json_field() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"\\\\]*\\).*/\\1/p" | head -1
}

# --- the ruleset ----------------------------------------------------------
# Filters rules.md to the active level. Lines tagged [lite]/[full]/[ultra] are
# level-specific; every other line always applies. Because we own the file we
# tag lines explicitly instead of pattern-matching markdown structure, which is
# what made the equivalent filter in ponytail fragile.
ruleset() {
  if [ -r "$RULES" ]; then
    awk -v lvl="$1" '
      /^<!--/ {inc=1}
      inc     {if (/-->/) inc=0; next}
      /^\[/ {
        tag=$0;  sub(/^\[/,"",tag); sub(/\].*/,"",tag)
        rest=$0; sub(/^\[[^]]*\][ \t]*/,"",rest)
        n=split(tag,a,",")
        for(i=1;i<=n;i++) if(a[i]==lvl) {print rest; next}
        next
      }
      {print}
    ' "$RULES"
  else
    fallback_rules
  fi
  if [ -r "$NATIVE" ]; then
    printf '\nBefore adding any dependency, check %s - it maps common packages to the stdlib or platform feature that already covers them.\n' "$NATIVE"
  fi
}

# Used only when rules.md is unreadable, so the ruleset never silently vanishes.
fallback_rules() {
  cat <<'FB'
# Lean execution

Before writing code, stop at the first rung that holds: does it need to exist
at all; is it already in this codebase; does the stdlib do it; does a native
platform feature cover it; does an installed dependency solve it; can it be one
line; only then the minimum that works. The ladder runs after you understand
the problem, never instead of it.

Grep or Glob to locate before reading; read only the ranges you need. Send wide
searches to a subagent so raw output stays out of this window.

Answer first, then at most three short lines. If the explanation is longer than
the code, delete the explanation. Requested explanation is exempt.

Never simplify away input validation at trust boundaries, error handling that
prevents data loss, security, accessibility, or anything explicitly requested.

A procedure worth repeating gets captured with the skill-capture skill, not
added to CLAUDE.md.
FB
}

# Signatures seen THRESHOLD+ times with neither a matching skill directory nor
# a previous suggestion.
pending_repeats() {
  SIGFILE="$DATA/signals/$HASH.tsv"
  [ -r "$SIGFILE" ] || return 0
  SUGGESTED="$DATA/state/$HASH.suggested"
  FOUND=""
  REPS="$(cut -f1 "$SIGFILE" 2>/dev/null | sort | uniq -c | awk -v t="$THRESHOLD" '$1>=t {print $2}' | head -5)"
  for SIG in $REPS; do
    [ -d "$PROJ/.claude/skills/$SIG" ] && continue
    if [ -f "$SUGGESTED" ] && grep -qxF "$SIG" "$SUGGESTED" 2>/dev/null; then
      continue
    fi
    FOUND="${FOUND:+$FOUND, }$SIG"
    mkdir -p "$DATA/state" 2>/dev/null && printf '%s\n' "$SIG" >> "$SUGGESTED" 2>/dev/null
  done
  printf '%s' "$FOUND"
}

# --- session --------------------------------------------------------------
do_session() {
  LEVEL="$(resolve_level)"
  [ "$LEVEL" = "off" ] && exit 0
  OUT=""

  # Bootstrap: offer once per project, then never nag. Repeating it every
  # session start turns a helpful hint into a nag.
  OFFERED="$DATA/state/$HASH.offered"
  if [ ! -f "$OFFERED" ]; then
    if [ ! -f "$PROJ/CLAUDE.md" ] || ! grep -q '^## Context layout' "$PROJ/CLAUDE.md" 2>/dev/null; then
      OUT="context-kit: this project has no context layout yet. Use the context-cleanup skill in Mode 0 now - it scaffolds the layout and creates or appends the CLAUDE.md block - then carry on with whatever was asked."
      mkdir -p "$DATA/state" 2>/dev/null && : > "$OFFERED" 2>/dev/null
    fi
  fi

  REPEATS="$(pending_repeats)"
  if [ -n "$REPEATS" ]; then
    NOTE="context-kit: these procedures repeated ${THRESHOLD}+ times and no skill covers them: ${REPEATS}. Capture the genuinely repeatable ones with the skill-capture skill."
    if [ -n "$OUT" ]; then
      OUT="$OUT
$NOTE"
    else
      OUT="$NOTE"
    fi
  fi

  if [ -n "$OUT" ]; then
    { printf '%s\n\n' "$OUT"; ruleset "$LEVEL"; } | emit SessionStart
  else
    ruleset "$LEVEL" | emit SessionStart
  fi
}

# --- subagent -------------------------------------------------------------
# SessionStart context is parent-thread only and never reaches subagents, so
# without this every Task-spawned agent runs rules-unaware. SubagentStart also
# requires the hookSpecificOutput form or the context is dropped.
do_subagent() {
  LEVEL="$(resolve_level)"
  [ "$LEVEL" = "off" ] && exit 0
  ruleset "$LEVEL" | emit SubagentStart
}

# --- mode switch ----------------------------------------------------------
# Whole-message match only. Matching these phrases anywhere in the message turns
# the ruleset off mid-task for ordinary requests like "add a normal mode toggle".
do_mode() {
  PROMPT="$(json_field prompt)"
  [ -n "$PROMPT" ] || exit 0
  CLEAN="$(printf '%s' "$PROMPT" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]!.]*$//')"
  case "$CLEAN" in
    "/lean lite")  NEW=lite ;;
    "/lean full")  NEW=full ;;
    "/lean ultra") NEW=ultra ;;
    "/lean off"|"stop lean"|"normal mode") NEW=off ;;
    "/lean") NEW="" ;;
    *) exit 0 ;;
  esac
  if [ -n "$NEW" ]; then
    mkdir -p "$DATA" 2>/dev/null && printf '%s\n' "$NEW" > "$DATA/level" 2>/dev/null
    LEVEL="$NEW"
  else
    LEVEL="$(resolve_level)"
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"context-kit level is now: %s","systemMessage":"context-kit: level %s"}}\n' "$LEVEL" "$LEVEL"
}

# --- signal ledger --------------------------------------------------------
# Silent and append-only. Never writes to stdout: this runs on every Bash call.
do_signal() {
  [ "${CONTEXT_KIT_NO_SIGNALS:-}" = "1" ] && exit 0
  CMD="$(json_field command)"
  [ -n "$CMD" ] || exit 0
  SIG="$(printf '%s' "$CMD" | awk '{print $1" "$2}' | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
  [ -n "$SIG" ] || exit 0
  case "$SIG" in
    ls|ls-*|cd|cd-*|cat|cat-*|echo|echo-*|pwd|which|which-*|head|head-*|tail|tail-*|git-status|git-diff|git-log|grep|grep-*|find|find-*|mkdir|mkdir-*|rm|rm-*|cp|cp-*|mv|mv-*|sed|sed-*|awk|awk-*|wc|wc-*|true|exit)
      exit 0 ;;
  esac
  SIGDIR="$DATA/signals"
  mkdir -p "$SIGDIR" 2>/dev/null || exit 0
  SIGFILE="$SIGDIR/$HASH.tsv"
  printf '%s\t%s\n' "$SIG" "$(date +%s 2>/dev/null)" >> "$SIGFILE" 2>/dev/null
  LINES="$(wc -l < "$SIGFILE" 2>/dev/null | tr -d ' ')"
  if [ -n "$LINES" ] && [ "$LINES" -gt 1000 ] 2>/dev/null; then
    tail -n 500 "$SIGFILE" > "$SIGFILE.tmp" 2>/dev/null && mv "$SIGFILE.tmp" "$SIGFILE" 2>/dev/null
  fi
  exit 0
}

case "$ACTION" in
  session)  do_session ;;
  subagent) do_subagent ;;
  mode)     do_mode ;;
  signal)   do_signal ;;
  *)        exit 0 ;;
esac
exit 0
