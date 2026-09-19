#!/bin/sh
# context-kit hook entrypoint. POSIX sh, no external runtime.
#
# Usage: context-kit.sh session|subagent|mode|signal|event
#
# Fails open, always. Every error path exits 0 with no output: a broken hook
# must never block a session. Hook engineering patterns (fail-open, once-only
# nudges, whole-message deactivation, hardcoded fallback) are adapted from
# ponytail (MIT, Dietrich Gebert). The command-signature normalizer and the
# atomic once-per-session claim are adapted from graphify (Apache-2.0,
# Graphify Labs). See NOTICE.

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

# Claim a one-time action for this project, atomically. mkdir is the POSIX
# primitive that either creates or fails - test-then-write races when two
# subagents start together. Returns 0 only for the first caller, so a nudge
# fires at most once and can never strand the agent by repeating. Adapted
# from graphify's _mark_session_denied, which uses O_EXCL for the same reason.
claim_once() {
  mkdir -p "$DATA/state" 2>/dev/null || return 1
  mkdir "$DATA/state/$HASH.$1.lock" 2>/dev/null || return 1
  return 0
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
  # The legacy flag file keeps an existing install from being re-offered on
  # upgrade; claim_once is what makes it safe when two sessions start at once.
  OFFERED="$DATA/state/$HASH.offered"
  if [ ! -f "$OFFERED" ]; then
    if [ ! -f "$PROJ/CLAUDE.md" ] || ! grep -q '^## Context layout' "$PROJ/CLAUDE.md" 2>/dev/null; then
      if claim_once offered; then
        OUT="context-kit: this project has no context layout yet. Use the context-cleanup skill in Mode 0 now - it scaffolds the layout and creates or appends the CLAUDE.md block - then carry on with whatever was asked."
        : > "$OFFERED" 2>/dev/null
      fi
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

# --- command signature ----------------------------------------------------
# Reduce a shell command to the procedure it actually runs.
#
# The old form - first two whitespace tokens of the raw string - gave `pytest
# -k x`, `sudo pytest -k x` and `env CI=1 pytest -k x` three different
# signatures, so a procedure repeated in three shapes never reached the
# threshold. It also read tokens out of quoted arguments and heredoc bodies,
# so `git commit -m "run the deploy"` contributed whatever happened to land in
# position two.
#
# Instead: drop heredoc bodies and quoted spans, keep the first command
# segment, skip VAR=value prefixes and wrapper words (with their own flags),
# then emit "<exe> <first non-flag argument>". Adapted from graphify's
# _bash_invokes_search, which fixes the same class of false positive.
signature() {
  awk '
    function is_wrapper(w) {
      return (w=="sudo"||w=="doas"||w=="command"||w=="exec"||w=="nohup"||
              w=="time"||w=="nice"||w=="ionice"||w=="env"||w=="xargs"||
              w=="timeout"||w=="stdbuf")
    }
    {
      # Join the whole command; heredoc bodies were already stripped upstream.
      buf = (NR==1 ? $0 : buf " " $0)
    }
    END {
      # Drop quoted spans - anything quoted is an argument, never the exe.
      gsub(/'"'"'[^'"'"']*'"'"'/, " ", buf)
      gsub(/"[^"]*"/, " ", buf)
      # First command segment only.
      sub(/[|;&].*/, "", buf)
      sub(/^[ \t]+/, "", buf)
      n = split(buf, t, /[ \t]+/)
      i = 1
      while (i <= n) {
        tok = t[i]
        if (tok == "") { i++; continue }
        # VAR=value prefix (an "=" before any slash-free trailing segment).
        if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
        # Strip any directory part and a .exe suffix.
        sub(/.*\//, "", tok)
        sub(/\.exe$/, "", tok)
        if (is_wrapper(tolower(tok))) {
          i++
          while (i <= n && t[i] ~ /^-/) i++
          continue
        }
        break
      }
      if (i > n) exit
      exe = tolower(t[i]); sub(/.*\//, "", exe); sub(/\.exe$/, "", exe)
      # A subcommand, and only a subcommand: the token immediately after the
      # exe, and only when it is a bare word. `npm run`, `git commit` and
      # `docker compose` are genuinely different procedures and must not
      # collapse; `-k auth` is a flag value and `tests/unit` is a path, and
      # keying on either would give every invocation its own signature so the
      # repeat threshold is never reached.
      arg = ""
      if (i + 1 <= n) {
        nxt = t[i + 1]
        if (nxt != "" && nxt !~ /^-/ && nxt !~ /[\/=]/) arg = tolower(nxt)
      }
      print exe (arg == "" ? "" : " " arg)
    }
  '
}

# Heredoc bodies never describe what ran, so drop them before signing. A
# heredoc that is never terminated runs to the end of the input.
strip_heredocs() {
  awk '
    /<<-?[ \t]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*['"'"'"]?/ && !inbody {
      line = $0
      if (match(line, /<<-?[ \t]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*['"'"'"]?/)) {
        tag = substr(line, RSTART, RLENGTH)
        gsub(/^<<-?[ \t]*/, "", tag); gsub(/['"'"'"]/, "", tag)
        term = tag; inbody = 1
      }
      print; next
    }
    inbody { if ($0 ~ "^[ \t]*" term "[ \t]*$") inbody = 0; next }
    { print }
  '
}

# --- signal ledger --------------------------------------------------------
# Silent and append-only. Never writes to stdout: this runs on every Bash call.
do_signal() {
  [ "${CONTEXT_KIT_NO_SIGNALS:-}" = "1" ] && exit 0
  CMD="$(json_field command)"
  [ -n "$CMD" ] || exit 0
  SIG="$(printf '%s\n' "$CMD" | strip_heredocs | signature | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
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

# --- activity ledger ------------------------------------------------------
# Who touched what. Silent, append-only, TSV: ts, kind, actor, target.
#
# This is the only record of the part of a session that leaves no artifact -
# which subagent was spawned for what, which files it read, which skills
# fired. /context-graph renders it as the activity layer over the static
# context layout; without it the graph shows the shelf and not the traffic.
#
# Records identifiers only - a tool name, a file path, a skill name, a
# subagent type. Never arguments, never file contents, never prompt text.
do_event() {
  [ "${CONTEXT_KIT_NO_SIGNALS:-}" = "1" ] && exit 0
  [ "${CONTEXT_KIT_NO_ACTIVITY:-}" = "1" ] && exit 0
  IN="$(cat 2>/dev/null)"
  [ -n "$IN" ] || exit 0

  SID="$(printf '%s' "$IN" | json_field session_id)"
  [ -n "$SID" ] || SID="session"
  ACTOR="$(printf '%s' "$SID" | tr -cs 'A-Za-z0-9' '-' | cut -c1-16)"
  [ -n "$ACTOR" ] || ACTOR="session"

  TOOL="$(printf '%s' "$IN" | json_field tool_name)"
  EVT="$(printf '%s' "$IN" | json_field hook_event_name)"

  KIND=""
  TARGET=""
  case "$EVT" in
    SubagentStart|SubagentStop)
      KIND="agent"
      TARGET="$(printf '%s' "$IN" | json_field subagent_type)"
      [ -n "$TARGET" ] || TARGET="$(printf '%s' "$IN" | json_field agent_type)"
      [ -n "$TARGET" ] || TARGET="subagent"
      ;;
  esac

  if [ -z "$KIND" ]; then
    case "$TOOL" in
      Read|NotebookRead)
        KIND="read";  TARGET="$(printf '%s' "$IN" | json_field file_path)" ;;
      Edit|Write|NotebookEdit)
        KIND="write"; TARGET="$(printf '%s' "$IN" | json_field file_path)" ;;
      Task)
        KIND="agent"
        TARGET="$(printf '%s' "$IN" | json_field subagent_type)"
        [ -n "$TARGET" ] || TARGET="subagent"
        ;;
      Skill)
        KIND="skill"; TARGET="$(printf '%s' "$IN" | json_field skill)" ;;
      *) exit 0 ;;
    esac
  fi

  [ -n "$TARGET" ] || exit 0

  # Paths are stored project-relative so the ledger stays portable and no
  # machine-specific prefix reaches the graph or the vault.
  case "$KIND" in
    read|write)
      case "$TARGET" in
        "$PROJ"/*) TARGET="${TARGET#"$PROJ"/}" ;;
        /*) exit 0 ;;  # outside the project: not ours to record
      esac
      ;;
  esac

  # A tab or newline in a value would desynchronize every later column.
  TARGET="$(printf '%s' "$TARGET" | tr '\t\n\r' '   ' | cut -c1-200)"
  case "$TARGET" in ""|" "*) exit 0 ;; esac

  EVDIR="$DATA/events"
  mkdir -p "$EVDIR" 2>/dev/null || exit 0
  EVFILE="$EVDIR/$HASH.tsv"
  printf '%s\t%s\t%s\t%s\n' "$(date +%s 2>/dev/null)" "$KIND" "$ACTOR" "$TARGET" >> "$EVFILE" 2>/dev/null
  LINES="$(wc -l < "$EVFILE" 2>/dev/null | tr -d ' ')"
  if [ -n "$LINES" ] && [ "$LINES" -gt 4000 ] 2>/dev/null; then
    tail -n 2000 "$EVFILE" > "$EVFILE.tmp" 2>/dev/null && mv "$EVFILE.tmp" "$EVFILE" 2>/dev/null
  fi
  exit 0
}

case "$ACTION" in
  session)  do_session ;;
  subagent) do_subagent ;;
  mode)     do_mode ;;
  signal)   do_signal ;;
  event)    do_event ;;
  *)        exit 0 ;;
esac
exit 0
