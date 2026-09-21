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

# Extract a string field from stdin JSON without jq.
#
# The previous implementation was a single sed with the capture class
# [^"\\]*, which stops at the first backslash or escaped quote. Measured
# against 1,050 real Bash commands from agent transcripts, 816 of them (78%)
# were truncated before the hook ever saw them, and 47 distinct commands
# collapsed onto the prefix "set -e" - which reaches signature() as the
# signature "set", passes THRESHOLD, and makes context-kit suggest a skill
# for a shell builtin. It was also unanchored (a "command" key anywhere in
# the payload matched, including inside tool_response) and greedy (with two
# matches on one line the last one won).
#
# This is a real JSON scanner instead. Pass a bare key to take the first
# match at any depth, or a dotted path like tool_input.command to scope it.
# Only scalar string values are returned; a key whose value is an object,
# array or number yields nothing, which every caller treats as "skip".
# Malformed input yields nothing and exits 0 - a hook must never break a
# session.
json_field() {
  awk -v want="$1" '
    # %c means "this codepoint" in gawk and "this byte" in mawk and busybox
    # awk, so one of them has to be told. WIDECHAR probes it with a literal
    # that is two bytes of UTF-8 and one character; without this, mawk
    # truncates \u2550 to its low byte and a box-drawing rule decodes as "P".
    function emit(cp) {
      if (cp < 128 || WIDECHAR) return sprintf("%c", cp)
      if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + (cp % 64))
      if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096),
                                     128 + int((cp % 4096) / 64), 128 + (cp % 64))
      return sprintf("%c%c%c%c", 240 + int(cp / 262144),
                     128 + int((cp % 262144) / 4096),
                     128 + int((cp % 4096) / 64), 128 + (cp % 64))
    }
    function hexval(h,   i, c, v, d) {
      v = 0
      for (i = 1; i <= length(h); i++) {
        d = index("0123456789abcdef", tolower(substr(h, i, 1))) - 1
        if (d < 0) return -1
        v = v * 16 + d
      }
      return v
    }
    # Walks the JSON string whose opening quote is at s[i].
    # decode=1 builds the value into STRVAL; decode=0 only finds the end,
    # which keeps the scan linear over payloads we are going to discard.
    # Sets STRNEXT past the closing quote. Returns 0 if it never closes.
    function jstring(s, i, decode,   out, c, e, n, cp, lo) {
      n = length(s); out = ""; i++
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") {
          e = substr(s, i + 1, 1); i += 2
          if (!decode) { if (e == "u") i += 4; continue }
          if (e == "n") out = out "\n"
          else if (e == "t") out = out "\t"
          else if (e == "r") out = out "\r"
          else if (e == "b") out = out sprintf("%c", 8)
          else if (e == "f") out = out sprintf("%c", 12)
          else if (e == "u") {
            cp = hexval(substr(s, i, 4))
            if (cp < 0) return 0
            i += 4
            # A high surrogate only means anything paired with its low half.
            if (cp >= 55296 && cp <= 56319 && substr(s, i, 2) == "\\u") {
              lo = hexval(substr(s, i + 2, 4))
              if (lo >= 56320 && lo <= 57343) {
                cp = 65536 + (cp - 55296) * 1024 + (lo - 56320)
                i += 6
              }
            }
            out = out emit(cp)
          }
          else out = out e   # \" \\ \/ and any unknown escape: keep the char
          continue
        }
        if (c == "\"") { STRVAL = out; STRNEXT = i + 1; return 1 }
        if (decode) out = out c
        i++
      }
      return 0
    }
    function pathnow(   p, d) {
      if (depth < 1) return ""
      if (want !~ /\./) return key[depth]
      p = key[1]
      for (d = 2; d <= depth; d++) p = p "." key[d]
      return p
    }
    # A JSON string cannot hold a raw newline, so every newline rejoined here
    # is whitespace between tokens. Buffering is required: values may contain
    # escaped newlines and the payload may be pretty-printed.
    BEGIN { WIDECHAR = (length("é") == 1) }
    { buf = (NR == 1 ? $0 : buf "\n" $0) }
    END {
      n = length(buf); depth = 0; i = 1
      while (i <= n) {
        c = substr(buf, i, 1)
        if (c == "{") { depth++; type[depth] = "o"; key[depth] = ""; wantkey[depth] = 1; i++; continue }
        if (c == "[") { depth++; type[depth] = "a"; key[depth] = ""; i++; continue }
        if (c == "}" || c == "]") { if (depth > 0) depth--; i++; continue }
        if (c == ",") { if (depth > 0 && type[depth] == "o") wantkey[depth] = 1; i++; continue }
        if (c == "\"") {
          if (depth > 0 && type[depth] == "o" && wantkey[depth]) {
            if (!jstring(buf, i, 1)) exit 0
            key[depth] = STRVAL; wantkey[depth] = 0
          } else if (pathnow() == want) {
            if (!jstring(buf, i, 1)) exit 0
            print STRVAL
            exit 0
          } else {
            if (!jstring(buf, i, 0)) exit 0
          }
          i = STRNEXT
          continue
        }
        i++
      }
    }
  ' 2>/dev/null
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
# Project-relative paths a bash command reads, one per line.
#
# The ledger was blind to these: its PostToolUse matcher only covered the
# file tools, so across 24 agents it recorded one read while the transcripts
# showed hundreds. Agents read with cat, sed -n and grep far more often than
# with the file tool.
#
# Gated on an allow-list of readers, per command segment, so `rm x.ts` is not
# recorded as a read and `cd /repo && cat a.ts` still is. Tokenizing stays
# deliberately crude - quotes are dropped and the text split on whitespace -
# because the caller's [ -f ] test is the real filter: a fragment like "foo"
# out of a quoted regex simply is not a file. Tokens holding a $ are skipped
# rather than guessed at, which loses "$B/x.go" and is the right trade.
# One path, normalized and made project-relative, or nothing if it lands
# outside. Same rules as read_paths uses internally; both callers need them,
# and a containment guard that exists in two versions is a guard that will
# drift.
rel_path() {
  awk -v proj="$PROJ" -v p="$1" '
    BEGIN {
      if (p == "") exit
      if (substr(p, 1, 1) != "/") p = proj "/" p
      n = split(p, parts, "/")
      k = 0
      for (i = 1; i <= n; i++) {
        if (parts[i] == "" || parts[i] == ".") continue
        if (parts[i] == "..") { if (k > 0) k--; else exit; continue }
        k++; out[k] = parts[i]
      }
      res = ""
      for (i = 1; i <= k; i++) res = res "/" out[i]
      if (index(res, proj "/") != 1) exit
      print substr(res, length(proj) + 2)
    }
  ' 2>/dev/null
}

read_paths() {
  awk -v proj="$PROJ" '
    function is_reader(w) {
      return (w=="cat"||w=="head"||w=="tail"||w=="less"||w=="more"||w=="sed"||
              w=="awk"||w=="grep"||w=="egrep"||w=="fgrep"||w=="rg"||w=="ag"||
              w=="wc"||w=="diff"||w=="cmp"||w=="od"||w=="xxd"||w=="jq"||
              w=="yq"||w=="nl"||w=="strings"||w=="file"||w=="source"||w==".")
    }
    function is_wrapper(w) {
      return (w=="sudo"||w=="doas"||w=="command"||w=="exec"||w=="nohup"||
              w=="time"||w=="nice"||w=="ionice"||w=="env"||w=="xargs"||
              w=="timeout"||w=="stdbuf")
    }
    function is_preamble(w) {
      return (w=="cd"||w=="set"||w=="export"||w=="unset"||w=="pushd"||
              w=="popd"||w=="shopt"||w=="umask"||w=="ulimit"||w=="alias"||
              w=="for"||w=="while"||w=="until"||w=="if"||w=="then"||
              w=="elif"||w=="else"||w=="fi"||w=="do"||w=="done"||w=="case"||
              w=="esac"||w=="function"||w=="{"||w=="}"||w=="("||w==")")
    }
    # Lexical, not filesystem: resolve . and .. and require the result to sit
    # inside the project. do_event relativizes only ABSOLUTE paths, so without
    # this a relative ../../etc/passwd would reach the ledger verbatim and
    # walk straight past the guard that rejects the absolute form.
    function scriptfirst(w) {
      return (w=="sed"||w=="awk"||w=="gawk"||w=="mawk"||w=="grep"||
              w=="egrep"||w=="fgrep"||w=="rg"||w=="ag")
    }
    # Reject what read_paths can rule out on sight; [ -f ] does the rest.
    function emit(tok,   r) {
      if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*=/) return
      if (index(tok, "$") > 0) return
      if (tok ~ /^[0-9]+$/) return
      r = norm(tok)
      if (r != "") print r
    }
    function norm_abs(p,   n, parts, out, i, k, res) {
      n = split(p, parts, "/")
      k = 0
      for (i = 1; i <= n; i++) {
        if (parts[i] == "" || parts[i] == ".") continue
        if (parts[i] == "..") { if (k > 0) k--; else return ""; continue }
        k++; out[k] = parts[i]
      }
      res = ""
      for (i = 1; i <= k; i++) res = res "/" out[i]
      return res
    }
    function norm(p,   n, parts, out, i, k, res) {
      if (substr(p, 1, 1) != "/") p = base "/" p
      n = split(p, parts, "/")
      k = 0
      for (i = 1; i <= n; i++) {
        if (parts[i] == "" || parts[i] == ".") continue
        if (parts[i] == "..") { if (k > 0) k--; else return ""; continue }
        k++; out[k] = parts[i]
      }
      res = ""
      for (i = 1; i <= k; i++) res = res "/" out[i]
      if (index(res, proj "/") != 1) return ""
      return substr(res, length(proj) + 2)
    }
    { buf = (NR == 1 ? $0 : buf "\n" $0) }
    END {
      gsub(/["'"'"']/, " ", buf)
      for (r = 0; r < 8; r++) { if (!gsub(/\$\([^()]*\)/, " ", buf)) break }
      gsub(/`[^`]*`/, " ", buf)
      # Give redirect operators their own token so `cat a>b` parses like
      # `cat a > b`.
      gsub(/[0-9]*>>?|</, " & ", buf)
      base = proj
      ns = split(buf, seg, /[|;&\n]+/)
      for (s = 1; s <= ns && !stop; s++) {
        n = split(seg[s], t, /[ \t]+/)
        i = 1
        while (i <= n) {
          tok = t[i]
          if (tok == "") { i++; continue }
          if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
          sub(/.*\//, "", tok); sub(/\.exe$/, "", tok)
          if (is_wrapper(tolower(tok))) {
            i++
            while (i <= n && t[i] ~ /^-/) i++
            continue
          }
          break
        }
        if (i > n) continue
        exe = tolower(t[i]); sub(/.*\//, "", exe); sub(/\.exe$/, "", exe)

        # A cd moves the base for everything after it. One we cannot resolve
        # ends the walk: every later relative path would be measured from
        # the wrong root, and a wrong path is worse than a missing one.
        if (exe == "cd") {
          arg = ""
          for (j = i + 1; j <= n; j++) if (t[j] != "") { arg = t[j]; break }
          if (arg == "" || index(arg, "$") > 0) { stop = 1; break }
          base = norm_abs(substr(arg, 1, 1) == "/" ? arg : base "/" arg)
          if (base == "") { stop = 1; break }
          continue
        }
        if (is_preamble(exe) || !is_reader(exe)) continue

        pend = ""; skipnext = 0; nop = 0; sawpat = 0; noread = 0
        for (j = i + 1; j <= n; j++) {
          tok = t[j]
          if (tok == "") continue
          # Redirects were pre-spaced into tokens of their own above.
          if (tok ~ /^[0-9]*>>?$/) { pend = "w"; continue }
          if (tok == "<") { pend = "r"; continue }
          if (pend == "w") { pend = ""; continue }   # a > target is written
          if (pend == "r") { pend = ""; emit(tok); continue }
          if (substr(tok, 1, 1) == "-") {
            # -e supplies the pattern, so the first operand stops being one.
            if (tok == "-e" || tok == "--regexp") { sawpat = 1; skipnext = 1 }
            # -f supplies it from a file, and that file really is read.
            else if (tok == "-f" || tok == "--file") { sawpat = 1; pend = "r" }
            else if (tok ~ /^--(regexp|file)=/) sawpat = 1
            # sed -i rewrites in place. That is a write, and the ledger
            # already has a kind for writes.
            else if (exe == "sed" && tok ~ /^-[A-Za-z]*i/) noread = 1
            continue
          }
          if (skipnext) { skipnext = 0; continue }
          nop++
          if (noread) continue
          # For these the first bare operand is a regex or a program, not a
          # file - and `grep -n README.md check.sh` would otherwise record
          # the pattern purely because a file of that name happens to exist.
          if (scriptfirst(exe) && !sawpat && nop == 1) continue
          emit(tok)
        }
      }
    }
  '
}

signature() {
  awk '
    function is_wrapper(w) {
      return (w=="sudo"||w=="doas"||w=="command"||w=="exec"||w=="nohup"||
              w=="time"||w=="nice"||w=="ionice"||w=="env"||w=="xargs"||
              w=="timeout"||w=="stdbuf")
    }
    # Navigation and environment setup are how a command STARTS, not what it
    # does. Keying on the first segment made `cd /repo && npm run build` sign
    # as "cd" and `set -e; pytest` sign as "set": across 1,050 real commands
    # that collapsed 645 distinct ones onto "cd" and 53 onto "set", and "set"
    # cleared the repeat threshold and produced a skill suggestion for a
    # shell builtin.
    # Shell control words belong here too: `for f in ...; do npm run build;
    # done` is an npm procedure, not a "for" procedure.
    function is_preamble(w) {
      return (w=="cd"||w=="set"||w=="export"||w=="unset"||w=="pushd"||
              w=="popd"||w=="source"||w=="."||w=="shopt"||w=="umask"||
              w=="ulimit"||w=="alias"||w=="for"||w=="while"||w=="until"||
              w=="if"||w=="then"||w=="elif"||w=="else"||w=="fi"||w=="do"||
              w=="done"||w=="case"||w=="esac"||w=="function"||w=="{"||
              w=="}"||w=="("||w==")")
    }
    # "<exe> <subcommand>" for one command segment, or "" if it holds none.
    function seg_sig(seg,   n, t, i, tok, exe, arg, nxt) {
      sub(/^[ \t]+/, "", seg)
      n = split(seg, t, /[ \t]+/)
      i = 1
      while (i <= n) {
        tok = t[i]
        if (tok == "") { i++; continue }
        # VAR=value prefix.
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
      if (i > n) return ""
      exe = tolower(t[i]); sub(/.*\//, "", exe); sub(/\.exe$/, "", exe)
      # A subcommand, and only a subcommand: the token immediately after the
      # exe, and only when it is a bare word. `npm run`, `git commit` and
      # `docker compose` are genuinely different procedures and must not
      # collapse; `-k auth` is a flag value and `tests/unit` is a path, and
      # keying on either would give every invocation its own signature so the
      # repeat threshold is never reached.
      # Must be a bare word. A redirect is not a subcommand: without this,
      # `cat > out.txt` and `cat <<EOF` signed as "cat >" and "cat <<".
      arg = ""
      if (i + 1 <= n) {
        nxt = t[i + 1]
        if (nxt ~ /^[A-Za-z][A-Za-z0-9_.-]*$/) arg = tolower(nxt)
      }
      return exe (arg == "" ? "" : " " arg)
    }
    {
      # Keep the newlines: a pasted script is many commands, and joining them
      # with a space made the whole thing one segment, so the signature came
      # from whatever token happened to follow a pipe deep inside it - real
      # scripts signed as "sort" and "1".
      buf = (NR==1 ? $0 : buf "\n" $0)
    }
    END {
      # Drop quoted spans - anything quoted is an argument, never the exe.
      gsub(/'"'"'[^'"'"']*'"'"'/, " ", buf)
      gsub(/"[^"]*"/, " ", buf)
      # Command substitutions are arguments too. Innermost-first so nesting
      # unwinds; the guard stops a pathological input from spinning.
      for (r = 0; r < 8; r++) {
        if (!gsub(/\$\([^()]*\)/, " ", buf)) break
      }
      gsub(/`[^`]*`/, " ", buf)
      ns = split(buf, seg, /[|;&\n]+/)
      for (s = 1; s <= ns; s++) {
        sig = seg_sig(seg[s])
        if (sig == "") continue
        split(sig, w, " ")
        if (!is_preamble(w[1])) { print sig; exit }
      }
      # Every segment was navigation, setup or a control word. There is no
      # procedure here to key on, so emit nothing rather than key on the
      # scaffolding - do_signal treats empty as "skip".
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
  CMD="$(json_field tool_input.command)"
  [ -n "$CMD" ] || exit 0
  SIG="$(printf '%s\n' "$CMD" | strip_heredocs | signature | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
  [ -n "$SIG" ] || exit 0
  # Bare interpreters are denied without a -* form on purpose: `python3`
  # alone is someone running a throwaway script, but `python3 manage.py` is a
  # procedure and must still reach the threshold.
  case "$SIG" in
    ls|ls-*|cd|cd-*|cat|cat-*|echo|echo-*|pwd|which|which-*|head|head-*|tail|tail-*|git-status|git-diff|git-log|grep|grep-*|find|find-*|mkdir|mkdir-*|rm|rm-*|cp|cp-*|mv|mv-*|sed|sed-*|awk|awk-*|wc|wc-*|true|exit|\
    diff|diff-*|sort|sort-*|uniq|uniq-*|cut|cut-*|tr|tr-*|touch|touch-*|chmod|chmod-*|\
    set|export|unset|printf|test|basename|dirname|date|od|xxd|\
    sh|bash|zsh|node|python|python3|perl|ruby)
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
open_ledger() {
  EVDIR="$DATA/events"
  mkdir -p "$EVDIR" 2>/dev/null || return 1
  EVFILE="$EVDIR/$HASH.tsv"
  return 0
}

append_event() {
  # A tab or newline in a value would desynchronize every later column.
  _T="$(printf '%s' "$2" | tr '\t\n\r' '   ' | cut -c1-200)"
  case "$_T" in ""|" "*) return 0 ;; esac
  printf '%s\t%s\t%s\t%s\n' "$(date +%s 2>/dev/null)" "$1" "$ACTOR" "$_T" \
    >> "$EVFILE" 2>/dev/null
}

# Trim reads first and keep agent and skill events.
#
# The old rotation kept the last 2000 lines of anything. Once bash reads are
# recorded that is mostly reads, and context-graph.awk decides a skill was
# "never invoked in the recorded activity" from whatever survived - so
# rotation could manufacture that finding. Reads are both the bulk and the
# most disposable, so they are what gets dropped.
rotate_events() {
  # The redirect below fails in the shell, not in wc, so 2>/dev/null on wc
  # would not silence it - and a hook that writes to stderr taints every
  # tool call it runs on.
  [ -f "$EVFILE" ] || return 0
  LINES="$(wc -l < "$EVFILE" 2>/dev/null | tr -d ' ')"
  [ -n "$LINES" ] || return 0
  [ "$LINES" -gt 4000 ] 2>/dev/null || return 0
  { awk -F'\t' '$2=="agent"||$2=="skill"' "$EVFILE" 2>/dev/null | tail -n 1000
    awk -F'\t' '$2!="agent"&&$2!="skill"' "$EVFILE" 2>/dev/null | tail -n 2000
  } | sort -n -k1,1 > "$EVFILE.tmp" 2>/dev/null &&
    mv "$EVFILE.tmp" "$EVFILE" 2>/dev/null
}

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
        KIND="read";  TARGET="$(printf '%s' "$IN" | json_field tool_input.file_path)" ;;
      Edit|Write|NotebookEdit)
        KIND="write"; TARGET="$(printf '%s' "$IN" | json_field tool_input.file_path)" ;;
      Task)
        KIND="agent"
        TARGET="$(printf '%s' "$IN" | json_field tool_input.subagent_type)"
        [ -n "$TARGET" ] || TARGET="$(printf '%s' "$IN" | json_field subagent_type)"
        [ -n "$TARGET" ] || TARGET="subagent"
        ;;
      Skill)
        KIND="skill"; TARGET="$(printf '%s' "$IN" | json_field tool_input.skill)"
                      [ -n "$TARGET" ] || TARGET="$(printf '%s' "$IN" | json_field skill)" ;;
      Bash)
        # One command can read several files, so this case records its own
        # events and returns rather than falling through to the single-target
        # path below. sort -u collapses a file read twice in one command;
        # [ -f ] is what rejects the tokens read_paths could not rule out,
        # like a sed script or a quoted regex fragment.
        CMD="$(printf '%s' "$IN" | json_field tool_input.command)"
        [ -n "$CMD" ] || exit 0
        open_ledger || exit 0
        printf '%s\n' "$CMD" | strip_heredocs | read_paths | sort -u | head -n 40 |
          while IFS= read -r P; do
            [ -f "$PROJ/$P" ] || continue
            append_event read "$P"
          done
        rotate_events
        exit 0
        ;;
      *) exit 0 ;;
    esac
  fi

  [ -n "$TARGET" ] || exit 0

  # Paths are stored project-relative so the ledger stays portable and no
  # machine-specific prefix reaches the graph or the vault.
  case "$KIND" in
    read|write)
      # A relative path used to fall through both arms of the old case and
      # reach the ledger verbatim, so ../../etc/passwd walked straight past
      # the guard that rejects the absolute form.
      TARGET="$(rel_path "$TARGET")"
      [ -n "$TARGET" ] || exit 0
      ;;
  esac

  open_ledger || exit 0
  append_event "$KIND" "$TARGET"
  rotate_events
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
