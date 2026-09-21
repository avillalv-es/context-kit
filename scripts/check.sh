#!/bin/sh
# context-kit self-check. POSIX sh, no runtime beyond the shell.
#
# Run from the repo root:  sh scripts/check.sh
#
# Guards the mistakes that are invisible until a user hits them: a version that
# drifted between manifests, a SKILL.MD that vanishes on a case-sensitive
# filesystem, a hook that stopped emitting valid JSON, a skill description
# written as a capability instead of a trigger.

FAIL=0
note() { printf '  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAIL=1; }
pass() { printf 'ok    %s\n' "$1"; }

cd "$(dirname "$0")/.." || exit 1

# --- 1. version consistency ------------------------------------------------
# Every manifest staying stale together looks like agreement to a naive check,
# so compare the values rather than asserting they are all present.
PV=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .claude-plugin/plugin.json | head -1)
MV=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .claude-plugin/marketplace.json | head -1)
if [ -z "$PV" ]; then
  fail "plugin.json has no version"
elif [ -z "$MV" ]; then
  fail "marketplace.json plugin entry has no version (it can silently drift)"
elif [ "$PV" != "$MV" ]; then
  fail "version drift: plugin.json=$PV marketplace.json=$MV"
else
  pass "version $PV consistent across manifests"
fi

# --- 2. skill filenames ----------------------------------------------------
# SKILL.MD resolves on Windows and macOS and is invisible on a case-sensitive
# filesystem, which is where CI runs.
BAD=$(find skills -name 'SKILL.*' ! -name 'SKILL.md' 2>/dev/null)
if [ -n "$BAD" ]; then
  fail "non-lowercase skill files:"
  printf '%s\n' "$BAD" | sed 's/^/        /'
else
  pass "every skill file is SKILL.md"
fi

for d in skills/*/; do
  [ -f "$d/SKILL.md" ] || fail "missing $d/SKILL.md"
done

# --- 3. descriptions are triggers, not capabilities ------------------------
# The description is the entire firing mechanism. "Helps with X" matches
# nothing; a description must name when to use it.
# Track this check's own result: reusing the global flag would make one earlier
# failure silently suppress this check's verdict.
DESC_FAIL=0
for f in skills/*/SKILL.md; do
  D=$(sed -n '/^description:/,/^[a-z-]*:/p' "$f" | tr '\n' ' ')
  case "$D" in
    *"Use when"*|*"use when"*|*"Use immediately"*) : ;;
    *) fail "$f description is not written as a trigger (no \"use when\")"; DESC_FAIL=1 ;;
  esac
done
[ "$DESC_FAIL" -eq 0 ] && pass "every skill description is written as a trigger"

# --- 4. hooks emit valid-looking JSON --------------------------------------
TMP="${TMPDIR:-/tmp}/ck-check-$$"
mkdir -p "$TMP/data" "$TMP/proj" 2>/dev/null
for ACTION in session subagent; do
  OUT=$(CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$TMP/data" CLAUDE_PROJECT_DIR="$TMP/proj" sh hooks/context-kit.sh "$ACTION" 2>/dev/null)
  case "$OUT" in
    '{"hookSpecificOutput":{"hookEventName":"'*'additionalContext":"'*'}}') pass "hook $ACTION emits hookSpecificOutput" ;;
    *) fail "hook $ACTION emitted unexpected output: $(printf '%s' "$OUT" | head -c 80)" ;;
  esac
done

# signal must stay silent; it runs on every Bash call
SOUT=$(printf '%s' '{"tool_input":{"command":"pytest -k x"}}' | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$TMP/data" CLAUDE_PROJECT_DIR="$TMP/proj" sh hooks/context-kit.sh signal 2>/dev/null)
if [ -n "$SOUT" ]; then
  fail "hook signal wrote to stdout (it must be silent)"
else
  pass "hook signal is silent"
fi

# every failure path must exit 0; a broken hook must never block a session
for ACTION in session subagent mode signal event bogus; do
  printf 'not json' | CLAUDE_PLUGIN_ROOT=/nonexistent CLAUDE_PLUGIN_DATA=/nonexistent sh hooks/context-kit.sh "$ACTION" >/dev/null 2>&1
  [ $? -eq 0 ] || fail "hook $ACTION exited non-zero on bad input"
done
pass "hooks fail open on bad input and missing paths"

# --- 5. level filter keeps unconditional lines -----------------------------
# Dropping an ordinary rule that happens to start with a mode word is the bug
# this filter exists to avoid.
for L in lite full ultra; do
  R=$(CONTEXT_KIT_LEVEL="$L" CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$TMP/data" sh hooks/context-kit.sh subagent 2>/dev/null)
  case "$R" in
    *"Never simplify away"*) : ;;
    *) fail "level $L dropped the safety carve-out" ;;
  esac
  case "$R" in
    *"Level $L"*) : ;;
    *) fail "level $L did not emit its own level line" ;;
  esac
done
pass "level filter keeps unconditional lines at every level"

# --- 6. hooks.json references files that exist -----------------------------
for f in hooks/context-kit.sh hooks/context-kit.ps1 hooks/rules.md knowledge/platform-native.md \
         scripts/context-graph.sh scripts/context-graph.awk scripts/context-vault.awk \
         scripts/findings.sh scripts/findings.awk templates/graph/viewer.html; do
  [ -f "$f" ] || fail "missing $f"
done
pass "referenced hook and script files present"

# --- 7. the activity ledger stays silent -----------------------------------
# This runs on every Read, Edit, Write, Task and Skill call. One stray byte on
# stdout and every one of them carries it into the transcript.
EOUT=$(printf '%s' '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"'"$TMP/proj"'/a.py"}}' \
  | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$TMP/data" CLAUDE_PROJECT_DIR="$TMP/proj" sh hooks/context-kit.sh event 2>/dev/null)
if [ -n "$EOUT" ]; then
  fail "hook event wrote to stdout (it must be silent)"
else
  pass "hook event is silent"
fi
if [ -s "$TMP/data/events/$(printf '%s' "$TMP/proj" | cksum | cut -d' ' -f1).tsv" ]; then
  pass "hook event records to the ledger"
else
  fail "hook event recorded nothing"
fi
# The same escape wearing a relative hat. The old guard had one arm for
# "under the project" and one for "absolute and elsewhere", and a relative
# path matched neither, so it was written to the ledger verbatim - past the
# check immediately below, which only ever saw the absolute form.
printf '%s' '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"../../etc/passwd"}}' \
  | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$TMP/data" CLAUDE_PROJECT_DIR="$TMP/proj" sh hooks/context-kit.sh event >/dev/null 2>&1
if grep -q 'passwd' "$TMP/data/events/"*.tsv 2>/dev/null; then
  fail "a relative file_path escaped the project and was recorded"
else
  pass "a relative file_path climbing out of the project is rejected"
fi
# An in-project relative path must still be recorded, unchanged.
printf '%s' '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"a.py"}}' \
  | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$TMP/data" CLAUDE_PROJECT_DIR="$TMP/proj" sh hooks/context-kit.sh event >/dev/null 2>&1
if grep -q '	a.py$' "$TMP/data/events/"*.tsv 2>/dev/null; then
  pass "an in-project relative file_path is recorded as given"
else
  fail "an in-project relative file_path was dropped"
fi

# A read outside the project is not ours to record.
printf '%s' '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"/etc/passwd"}}' \
  | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$TMP/data" CLAUDE_PROJECT_DIR="$TMP/proj" sh hooks/context-kit.sh event >/dev/null 2>&1
if grep -q 'passwd' "$TMP/data/events/"*.tsv 2>/dev/null; then
  fail "hook event recorded a file outside the project"
else
  pass "hook event ignores files outside the project"
fi

# --- 7b. the JSON decoder ---------------------------------------------------
# The old json_field was a lone sed whose capture class stopped at the first
# backslash. Against 1,050 real bash commands it truncated 816 of them, and
# every fixture here was quote-free, which is exactly why nobody noticed.
EV="$TMP/data/events/$(printf '%s' "$TMP/proj" | cksum | cut -d' ' -f1).tsv"
# Sourcing the hook would run its dispatch and exit, so lift the function out.
sed -n '/^json_field() {/,/^}$/p' hooks/context-kit.sh > "$TMP/jf.sh"
jf() { ( . "$TMP/jf.sh"; json_field "$1" ) 2>/dev/null; }

DEC=$(printf '%s' '{"tool_input":{"command":"grep -n \"foo bar\" a.py"}}' | jf tool_input.command)
if [ "$DEC" = 'grep -n "foo bar" a.py' ]; then
  pass "decoder keeps a command past its first escaped quote"
else
  fail "decoder truncated an escaped quote: got [$DEC]"
fi

DEC=$(printf '%s' '{"tool_input":{"command":"set -e\ncd /tmp"}}' | jf tool_input.command | tr '\n' '|')
if [ "$DEC" = 'set -e|cd /tmp|' ]; then
  pass "decoder expands an escaped newline"
else
  fail "decoder mishandled \\n: got [$DEC]"
fi

DEC=$(printf '%s' '{"a":"ABC"}' | jf a)
if [ "$DEC" = "ABC" ]; then
  pass "decoder resolves a \\uXXXX escape"
else
  fail "decoder mishandled \\uXXXX: got [$DEC]"
fi

# A decoy key of the same name must not win. The old sed matched "command"
# anywhere in the payload, tool_response included, and preferred the last.
DEC=$(printf '%s' '{"tool_response":{"command":"DECOY"},"tool_input":{"command":"REAL"}}' | jf tool_input.command)
if [ "$DEC" = "REAL" ]; then
  pass "decoder scopes a lookup to its key path"
else
  fail "decoder picked the wrong key: got [$DEC]"
fi

DEC=$(printf '%s' '{"a":"unterminated' | jf a)
if [ -z "$DEC" ]; then
  pass "decoder stays quiet on malformed JSON"
else
  fail "decoder emitted something for malformed input: [$DEC]"
fi

# --- 7c. bash reads reach the ledger ---------------------------------------
# The matcher used to cover only the file tools, so across 24 measured agents
# the ledger caught one read while the transcripts showed hundreds.
mkdir -p "$TMP/proj/sub" 2>/dev/null
: > "$TMP/proj/sub/read-me.txt"
ev() { printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$TMP/data" \
       CLAUDE_PROJECT_DIR="$TMP/proj" sh hooks/context-kit.sh event >/dev/null 2>&1; }

ev '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"cat sub/read-me.txt"}}'
if grep -q 'sub/read-me.txt' "$EV" 2>/dev/null; then
  pass "a bash read reaches the ledger"
else
  fail "a bash read was not recorded"
fi

if [ "$(awk -F'\t' '$4=="sub/read-me.txt"' "$EV" 2>/dev/null | awk 'END{print NF}')" = "4" ]; then
  pass "ledger rows carry exactly four columns"
else
  fail "ledger row is not four tab-separated columns"
fi

# Relative paths bypass the absolute-path guard unless they are normalized,
# so this is the same escape as /etc/passwd wearing a different hat.
ev '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"cat ../../etc/passwd"}}'
if grep -q 'passwd' "$EV" 2>/dev/null; then
  fail "a relative path escaped the project and was recorded"
else
  pass "a relative path climbing out of the project is rejected"
fi

# Writing is not reading: recording `rm` as a read would be a lie.
ev '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"rm -rf sub"}}'
if grep -q 'read.*sub$' "$EV" 2>/dev/null; then
  fail "a non-reading command was recorded as a read"
else
  pass "only reading commands contribute reads"
fi

# A pattern operand is not a file, even when a file of that name exists.
ev '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"grep -n sub/read-me.txt sub/read-me.txt"}}'
if [ "$(grep -c 'sub/read-me.txt' "$EV" 2>/dev/null)" = "2" ]; then
  pass "a grep pattern is not recorded even when it names a real file"
else
  fail "grep recorded its pattern as a read"
fi

# A redirect target is written, not read, and the ledger has a kind for that.
: > "$TMP/proj/sub/out.txt"
ev '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"cat sub/read-me.txt > sub/out.txt"}}'
if grep -q 'out.txt' "$EV" 2>/dev/null; then
  fail "a redirect target was recorded as a read"
else
  pass "a redirect target is not recorded as a read"
fi

# sed -i rewrites the file; that is a write.
ev '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ sub/out.txt"}}'
if grep -q 'out.txt' "$EV" 2>/dev/null; then
  fail "sed -i was recorded as a read"
else
  pass "an in-place edit is not recorded as a read"
fi

# A resolvable cd moves the base; an unresolvable one must stop the walk
# rather than resolve later paths against the wrong root.
ev '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"cd sub && cat read-me.txt"}}'
if grep -q 'sub/read-me.txt' "$EV" 2>/dev/null; then
  pass "a cd moves the base for later paths"
else
  fail "a cd did not move the base"
fi
ev '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"cd $SOMEWHERE && cat read-me.txt"}}'
if grep -q '	read-me.txt$' "$EV" 2>/dev/null; then
  fail "an unresolvable cd still resolved a later path"
else
  pass "an unresolvable cd stops the walk"
fi

# --- 7f. /lean only fires on a whole message -------------------------------
# The case arms are exact matches, and the ps1 compares the trimmed whole
# string - but the old decoder cut the prompt at its first newline, so a
# multi-line message starting "/lean off" switched the level. That was a
# silent divergence between the two shells.
md() { printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$TMP/data" \
       CLAUDE_PROJECT_DIR="$TMP/proj" sh hooks/context-kit.sh mode 2>/dev/null; }
if [ -n "$(md '{"prompt":"/lean off"}')" ]; then
  pass "/lean off on its own still switches the level"
else
  fail "/lean off stopped working"
fi
if [ -z "$(md '{"prompt":"/lean off\nand then do the thing"}')" ]; then
  pass "/lean off followed by a request does not switch the level"
else
  fail "a multi-line prompt switched the level"
fi

# --- 7d. rotation keeps what the graph reasons about ------------------------
# context-graph.awk calls a skill "never invoked in the recorded activity"
# from whatever survived rotation, so evicting skill events invents findings.
ROT="$TMP/rot.tsv"
: > "$ROT"
i=0
while [ "$i" -lt 4200 ]; do
  printf '%s\tread\ts1\tf%s.txt\n' "$i" "$i" >> "$ROT"
  i=$((i + 1))
done
printf '%s\tskill\ts1\tcontext-cleanup\n' 9999 >> "$ROT"
printf '%s\tagent\ts1\texplorer\n' 9999 >> "$ROT"
sed -n '/^rotate_events() {/,/^}$/p' hooks/context-kit.sh > "$TMP/rot.sh"
( . "$TMP/rot.sh"; EVFILE="$ROT"; rotate_events ) 2>/dev/null
if grep -q 'context-cleanup' "$ROT" 2>/dev/null && grep -q 'explorer' "$ROT" 2>/dev/null; then
  pass "rotation keeps agent and skill events"
else
  fail "rotation evicted the agent or skill events"
fi
if [ "$(wc -l < "$ROT" | tr -d ' ')" -lt 4000 ]; then
  pass "rotation actually trims the ledger"
else
  fail "rotation did not trim"
fi

# --- 7e. the graph reads the ledger ----------------------------------------
# This branch of context-graph.awk had no end-to-end coverage at all.
GEV="$TMP/gev.tsv"
printf '1\tread\ts1\tREADME.md\n2\tskill\ts1\tcontext-cleanup\n3\tagent\ts1\texplorer\n' > "$GEV"
GJ=$(awk -f scripts/context-graph.awk -v root="$TMP/proj" -v events="$GEV" </dev/null 2>/dev/null)
for want in '"kind": "session"' '"kind": "skill"' '"kind": "agent"' '"kind": "file"'; do
  case "$GJ" in
    *"$want"*) ;;
    *) fail "graph lost $want from the ledger" ;;
  esac
done
pass "graph builds session, skill, agent and file nodes from the ledger"

# The activity layer had no cap while the code layer has had one since it
# landed; bash reads make that difference matter.
printf '' > "$GEV"
i=0
while [ "$i" -lt 200 ]; do
  printf '1\tread\ts1\tf%s.txt\n' "$i" >> "$GEV"
  printf '1\tread\ts1\tf%s.txt\n' "$i" >> "$GEV"
  i=$((i + 1))
done
NF_=$(awk -f scripts/context-graph.awk -v root="$TMP/proj" -v events="$GEV" -v actcap=20 </dev/null 2>/dev/null \
      | tr ',' '\n' | grep -c '"kind": "file"')
if [ "$NF_" -le 20 ]; then
  pass "activity layer honours actcap"
else
  fail "activity layer emitted $NF_ file nodes against a cap of 20"
fi

# --- 8. command signatures collapse wrapper forms --------------------------
# The whole point of the ledger is that one procedure has one signature. If
# `sudo pytest` and `pytest` count separately, neither ever reaches the
# repeat threshold and the suggestion never fires.
SIGDIR="$TMP/sigdata"; rm -rf "$SIGDIR"; mkdir -p "$SIGDIR"
for C in 'pytest -k auth' 'sudo pytest -q' 'env CI=1 pytest' 'pytest tests/unit'; do
  printf '{"tool_input":{"command":"%s"}}' "$C" \
    | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$SIGDIR" CLAUDE_PROJECT_DIR="$TMP/proj" \
      sh hooks/context-kit.sh signal >/dev/null 2>&1
done
DISTINCT=$(cut -f1 "$SIGDIR/signals/"*.tsv 2>/dev/null | sort -u | wc -l | tr -d ' ')
if [ "$DISTINCT" = "1" ]; then
  pass "signature collapses wrapper, env-prefix and flag forms onto one key"
else
  fail "four shapes of one pytest run produced $DISTINCT signatures, expected 1"
  cut -f1 "$SIGDIR/signals/"*.tsv 2>/dev/null | sort -u | sed 's/^/        /'
fi
# ...while still telling genuinely different procedures apart.
for C in 'npm run build' 'npm ci'; do
  printf '{"tool_input":{"command":"%s"}}' "$C" \
    | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$SIGDIR" CLAUDE_PROJECT_DIR="$TMP/proj" \
      sh hooks/context-kit.sh signal >/dev/null 2>&1
done
if [ "$(cut -f1 "$SIGDIR/signals/"*.tsv 2>/dev/null | sort -u | wc -l | tr -d ' ')" = "3" ]; then
  pass "signature keeps distinct subcommands distinct"
else
  fail "npm run and npm ci did not stay distinct"
fi

# --- 8b. measure-repo picks tasks from history, and spots a routing miss ---
# The point of this script is that it works on a real repo, where nobody gets
# to choose which changes it is scored on. A smoke test against a throwaway
# git history is enough to catch the two ways it can be wrong: sampling
# nothing, and reporting a clean sweep when a commit matched no rule.
MR="$TMP/mr"
mkdir -p "$MR/base/src" "$MR/tier/.claude/rules"
printf 'monolith line\n%.0s' $(seq 1 40) > "$MR/base/CLAUDE.md"
printf 'router\n' > "$MR/tier/CLAUDE.md"
printf 'paths:\n  - "src/**"\n---\nthe src rule\n' > "$MR/tier/.claude/rules/10-src.md"
mkdir -p "$MR/tier/src"
( cd "$MR/base" && git init -q . && printf 'a\n' > src/a.ts && printf 'b\n' > elsewhere.md &&
  git add -A && git -c user.email=t@t -c user.name=t commit -qm init &&
  printf 'aa\n' >> src/a.ts && git add -A && git -c user.email=t@t -c user.name=t commit -qm "covered" &&
  printf 'bb\n' >> elsewhere.md && git add -A && git -c user.email=t@t -c user.name=t commit -qm "uncovered"
) >/dev/null 2>&1
MROUT=$(sh ab/measure-repo.sh "$MR/base" "$MR/tier" --commits 10 --out "$MR/out" 2>&1)
# Two, not three: the root commit has no parent to diff against, so it
# yields no file list and drops out.
case "$MROUT" in
  *"2 sampled"*) pass "measure-repo samples commits from history" ;;
  *) fail "measure-repo did not sample the expected commits" ;;
esac
# The commit touching only elsewhere.md matches no rule; the one touching
# src/a.ts does. A report of zero misses would mean the check cannot see them.
case "$MROUT" in
  *"routing misses  0 of"*) fail "measure-repo missed a commit that matched no rule" ;;
  *"routing misses"*) pass "measure-repo counts commits that matched no rule" ;;
  *) fail "measure-repo printed no routing-miss line" ;;
esac
if [ -f "$MR/out/repo-static.tsv" ]; then
  pass "measure-repo writes its aggregate TSV"
else
  fail "measure-repo wrote no aggregate"
fi

# --- 9. the sh and ps1 twins handle the same actions -----------------------
# They are registered for the same events, so an action one of them silently
# drops is a feature that exists on Linux and not on Windows.
PARITY=0
for A in session subagent mode signal event; do
  grep -q "^  $A)" hooks/context-kit.sh 2>/dev/null || { fail "sh hook does not handle '$A'"; PARITY=1; }
  grep -q "'$A'" hooks/context-kit.ps1 2>/dev/null || { fail "ps1 hook does not handle '$A'"; PARITY=1; }
done
[ "$PARITY" -eq 0 ] && pass "sh and ps1 hooks handle the same actions"

# Handling the same action names is not the same as agreeing on an answer.
# Both twins parse commands and paths independently, so they can and did
# drift: before this suite grew, sh switched the level on a multi-line
# "/lean off" and ps1 did not. Run the real comparison wherever a PowerShell
# exists, and say plainly when there is none rather than implying coverage.
PWSH="${CONTEXT_KIT_PWSH:-$(command -v pwsh 2>/dev/null)}"
if [ -n "$PWSH" ] && [ -x "$PWSH" ]; then
  PP="$TMP/parity"; mkdir -p "$PP/sub"
  : > "$PP/a.md"; : > "$PP/b.md"; : > "$PP/sub/c.md"
  DRIFT=0
  twin() { # $1 action, $2 payload, $3 which ledger column to compare
    rm -rf "$TMP/p_sh" "$TMP/p_ps"
    printf '%s' "$2" | CLAUDE_PLUGIN_DATA="$TMP/p_sh" CLAUDE_PROJECT_DIR="$PP" \
      sh hooks/context-kit.sh "$1" >/dev/null 2>&1
    printf '%s' "$2" | CLAUDE_PLUGIN_DATA="$TMP/p_ps" CLAUDE_PROJECT_DIR="$PP" \
      "$PWSH" -NoLogo -NoProfile -File hooks/context-kit.ps1 "$1" >/dev/null 2>&1
    A=$(cat "$TMP/p_sh/$3"/*.tsv 2>/dev/null | cut -f"$4" | sort | tr '\n' ' ')
    B=$(cat "$TMP/p_ps/$3"/*.tsv 2>/dev/null | cut -f"$4" | sort | tr '\n' ' ')
    [ "$A" = "$B" ] || { fail "sh and ps1 disagree on $5: sh=[$A] ps=[$B]"; DRIFT=1; }
  }
  twin event '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"cat a.md b.md"}}' events 4 "a multi-file read"
  twin event '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"grep -n a.md b.md"}}' events 4 "a pattern that names a file"
  twin event '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"cat a.md > b.md"}}' events 4 "a redirect target"
  twin event '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"cd sub && cat c.md"}}' events 4 "a cd that moves the base"
  twin event '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"cat ../../etc/passwd"}}' events 4 "a path escaping the project"
  twin event '{"session_id":"s1","tool_name":"Read","tool_input":{"file_path":"../../etc/passwd"}}' events 4 "a relative escaping file_path"
  twin signal '{"tool_input":{"command":"cd /x && npm run build"}}' signals 1 "a cd-prefixed signature"
  twin signal '{"tool_input":{"command":"set -e"}}' signals 1 "a scaffolding-only signature"
  MA=$(printf '%s' '{"prompt":"/lean off\nplus more"}' | CLAUDE_PROJECT_DIR="$PP" sh hooks/context-kit.sh mode 2>/dev/null)
  MB=$(printf '%s' '{"prompt":"/lean off\nplus more"}' | CLAUDE_PROJECT_DIR="$PP" "$PWSH" -NoLogo -NoProfile -File hooks/context-kit.ps1 mode 2>/dev/null)
  [ "$MA" = "$MB" ] || { fail "sh and ps1 disagree on a multi-line /lean prompt"; DRIFT=1; }
  [ "$DRIFT" -eq 0 ] && pass "sh and ps1 agree on signatures, read paths and mode"
else
  pass "sh/ps1 behaviour comparison skipped (no pwsh; set CONTEXT_KIT_PWSH to run it)"
fi

# --- 10. the graph builder emits parseable JSON ----------------------------
GP="$TMP/gproj"
rm -rf "$GP"; mkdir -p "$GP/.claude/rules" "$GP/.claude/skills/thing" "$GP/knowledge" "$GP/src"
printf '# P\n\n[knowledge](knowledge/INDEX.md)\n' > "$GP/CLAUDE.md"
printf -- '---\ndescription: Use when touching src.\npaths:\n  - "src/**"\n---\n# R\n- a rule\n' > "$GP/.claude/rules/r.md"
printf -- '---\ndescription: Use when asked to thing.\npaths:\n  - "nowhere/**"\n---\n# Gone\n' > "$GP/.claude/rules/dead.md"
printf -- '---\nname: thing\ndescription: Use when the user asks to thing.\n---\n# Thing\n' > "$GP/.claude/skills/thing/SKILL.md"
printf '# Index\n' > "$GP/knowledge/INDEX.md"
printf 'x\n' > "$GP/src/a.py"
GOUT="$TMP/gout"
if CLAUDE_PLUGIN_DATA="$TMP/nodata" sh scripts/context-graph.sh build --root "$GP" --out "$GOUT" >/dev/null 2>&1; then
  if [ -s "$GOUT/graph.json" ]; then
    # Structural check without a JSON parser: balanced braces, and every key
    # the viewer and the skill actually read.
    BAL=$(awk '{n+=gsub(/\{/,"{"); n-=gsub(/\}/,"}")} END{print n+0}' "$GOUT/graph.json")
    MISSING=""
    for K in '"nodes"' '"edges"' '"issues"' '"stats"' '"generated"'; do
      grep -q "$K" "$GOUT/graph.json" || MISSING="$MISSING $K"
    done
    if [ "$BAL" != "0" ]; then
      fail "graph.json braces unbalanced (depth $BAL) - it will not parse"
    elif [ -n "$MISSING" ]; then
      fail "graph.json missing key(s):$MISSING"
    else
      pass "graph builder emits structurally valid graph.json"
    fi
    grep -q 'can never fire' "$GOUT/graph.json" \
      && pass "graph builder flags a rule whose paths match nothing" \
      || fail "graph builder missed the unmatchable rule"
    grep -q '"covers"' "$GOUT/graph.json" \
      && pass "graph builder resolves rule paths against the tree" \
      || fail "graph builder emitted no covers edges"
  else
    fail "graph build wrote no graph.json"
  fi
  if [ -s "$GOUT/graph.html" ]; then
    grep -q '__CONTEXT_GRAPH_DATA__' "$GOUT/graph.html" \
      && fail "graph.html still contains the data placeholder" \
      || pass "graph.html has its data inlined"
  else
    fail "graph build wrote no graph.html"
  fi
else
  fail "graph build failed on a synthetic project"
fi

# A project with no layout must say so and exit non-zero, not write an empty
# graph that later reads as "you have nothing".
rm -rf "$TMP/bare"; mkdir -p "$TMP/bare"
if sh scripts/context-graph.sh build --root "$TMP/bare" --out "$TMP/bareout" >/dev/null 2>&1; then
  fail "graph build succeeded on a project with no context layout"
else
  pass "graph build refuses a project with no context layout"
fi

# --- 11. the viewer is self-contained --------------------------------------
# It has to open on a machine with no network. One CDN script tag is enough
# to make it a blank page on an air-gapped host.
EXT=$(grep -cE 'src=|href=|https?://|fetch\(|XMLHttpRequest|import ' templates/graph/viewer.html 2>/dev/null)
if [ "$EXT" = "0" ]; then
  pass "viewer loads nothing external"
else
  fail "viewer references something external ($EXT hit(s)) - it must work offline"
  grep -nE 'src=|href=|https?://|fetch\(|XMLHttpRequest|import ' templates/graph/viewer.html | head -5 | sed 's/^/        /'
fi

# --- 12. serve is loopback-first -------------------------------------------
MINB="$TMP/minbin"; rm -rf "$MINB"; mkdir -p "$MINB"
for t in sh awk find date cksum mkdir mv rm cut wc cat sed grep tr head tail sort uniq dirname; do
  bp=$(command -v "$t" 2>/dev/null) && ln -sf "$bp" "$MINB/$t"
done
WARN=$(PATH="$MINB" sh scripts/context-graph.sh serve --root "$GP" --out "$GOUT" --host 0.0.0.0 2>&1)
case "$WARN" in
  *WARNING*no\ authentication*) pass "serve warns before binding beyond loopback" ;;
  *) fail "serve did not warn about binding 0.0.0.0" ;;
esac
case "$WARN" in
  *"no HTTP server on this machine"*) pass "serve degrades to a file:// URL with no server available" ;;
  *) fail "serve did not fall back when no HTTP server exists" ;;
esac
grep -q 'host 127.0.0.1\|HOST=127.0.0.1' scripts/context-graph.sh \
  && pass "serve defaults to loopback" \
  || fail "serve does not default to 127.0.0.1"

# --- 13. the vault never overwrites a file it did not write ----------------
VD="$TMP/vault"; rm -rf "$VD"; mkdir -p "$VD"
printf 'MINE\n' > "$VD/thing.md"
CLAUDE_PLUGIN_DATA="$TMP/nodata" sh scripts/context-graph.sh vault --root "$GP" --out "$GOUT" --dir "$VD" >/dev/null 2>&1
if [ "$(cat "$VD/thing.md" 2>/dev/null)" = "MINE" ]; then
  pass "vault leaves a pre-existing note it did not create alone"
else
  fail "vault overwrote a note it did not create"
fi
[ -f "$VD/_MAP.md" ] && pass "vault writes its index" || fail "vault wrote no _MAP.md"

# --- 14. findings reflect is deterministic ---------------------------------
FD="$TMP/fproj"; rm -rf "$FD"; mkdir -p "$FD/findings"
printf '## 2026-01-01 - a\n\n**Question:** q1\n\n**Finding:** f\n\n**Outcome:** useful\n\n**Sources:** x.py\n' > "$FD/findings/a.md"
printf '\n## 2026-01-02 - b\n\n**Question:** q2\n\n**Finding:** f\n\n**Outcome:** useful\n\n**Sources:** x.py\n' >> "$FD/findings/a.md"
printf '\n## 2026-01-03 - c\n\n**Question:** q3\n\n**Finding:** f\n\n**Outcome:** dead_end\n\n**Sources:** y.py\n' >> "$FD/findings/a.md"
if sh scripts/findings.sh reflect --root "$FD" >/dev/null 2>&1; then
  cp "$FD/findings/LESSONS.md" "$TMP/l1.md"
  sh scripts/findings.sh reflect --root "$FD" >/dev/null 2>&1
  if cmp -s "$TMP/l1.md" "$FD/findings/LESSONS.md"; then
    pass "findings reflect is byte-stable across runs"
  else
    fail "findings reflect drifted between two runs on identical input"
  fi
  grep -q 'Preferred sources' "$FD/findings/LESSONS.md" \
    && pass "findings reflect promotes a corroborated source" \
    || fail "two useful entries did not promote a source to preferred"
  grep -q 'Known dead ends' "$FD/findings/LESSONS.md" \
    && pass "findings reflect records dead ends" \
    || fail "findings reflect dropped the dead end"
  # One entry must never mint a trusted source.
  printf '## 2026-01-04 - d\n\n**Question:** q4\n\n**Finding:** f\n\n**Outcome:** useful\n\n**Sources:** lonely.py\n' > "$FD/findings/b.md"
  sh scripts/findings.sh reflect --root "$FD" >/dev/null 2>&1
  if awk '/^## Preferred sources/,/^## /' "$FD/findings/LESSONS.md" | grep -q 'lonely.py'; then
    fail "a single entry promoted a source to preferred"
  else
    pass "a single entry stays tentative, never preferred"
  fi
else
  fail "findings reflect failed on a synthetic log"
fi

# --- 15. skills stay inside the loading budget -----------------------------
# A SKILL.md loads whole the moment it fires. Past ~12KB the reference half
# should be a references/ sidecar so only the decision path is paid for.
BUDGET_FAIL=0
for f in skills/*/SKILL.md; do
  SZ=$(wc -c < "$f" | tr -d ' ')
  D=$(dirname "$f")
  if [ "$SZ" -gt 12000 ] && [ ! -d "$D/references" ]; then
    fail "$f is $((SZ / 1024))KB with no references/ - split the reference half out"
    BUDGET_FAIL=1
  fi
done
[ "$BUDGET_FAIL" -eq 0 ] && pass "every skill is within the loading budget"

# --- 16. the import extractor, per language fixture ------------------------
# Each tests/fixtures/imports/<family>/ carries an EXPECTED.tsv of from->to
# edges the extractor must find. The fixtures deliberately include the traps:
# a commented-out import, an import inside a string literal, a multi-line
# import, a sibling module whose name is a prefix of the real one. A pass
# here means those produced no edge.
FIXROOT="tests/fixtures/imports"
if [ -d "$FIXROOT" ]; then
  FAM_FAIL=0
  FAM_N=0
  for FAM in "$FIXROOT"/*/; do
    [ -d "$FAM" ] || continue
    NAME="$(basename "$FAM")"
    EXP="$FAM/EXPECTED.tsv"
    [ -f "$EXP" ] || continue
    FAM_N=$((FAM_N + 1))
    FOUT="$TMP/fx-$NAME"
    if ! sh scripts/code-graph.sh --root "$FAM" --out "$FOUT" --quiet >/dev/null 2>&1; then
      fail "extractor crashed on the $NAME fixture"; FAM_FAIL=1; continue
    fi
    cut -f1,2 "$FOUT/imports.tsv" 2>/dev/null | sort -u > "$TMP/got-$NAME.tsv"
    grep -v '^#' "$EXP" | grep -v '^[[:space:]]*$' | sort -u > "$TMP/exp-$NAME.tsv"
    MISSING="$(comm -23 "$TMP/exp-$NAME.tsv" "$TMP/got-$NAME.tsv" 2>/dev/null)"
    EXTRA="$(comm -13 "$TMP/exp-$NAME.tsv" "$TMP/got-$NAME.tsv" 2>/dev/null)"
    if [ -n "$MISSING" ]; then
      fail "$NAME: edges the extractor should have found and did not:"
      printf '%s\n' "$MISSING" | head -8 | sed 's/^/        /'
      FAM_FAIL=1
    fi
    if [ -n "$EXTRA" ]; then
      fail "$NAME: edges the extractor invented:"
      printf '%s\n' "$EXTRA" | head -8 | sed 's/^/        /'
      FAM_FAIL=1
    fi
    [ -z "$MISSING" ] && [ -z "$EXTRA" ] && pass "$NAME fixture: every expected edge, and no invented ones"
  done
  if [ "$FAM_N" -eq 0 ]; then
    note "no language fixtures with an EXPECTED.tsv - extractor untested"
  fi

  # An unresolvable import must be DROPPED, never guessed into an edge. The
  # test: no edge may point outside the fixture it came from.
  LEAK=0
  for FAM in "$FIXROOT"/*/; do
    [ -d "$FAM" ] || continue
    NAME="$(basename "$FAM")"
    [ -f "$TMP/fx-$NAME/imports.tsv" ] || continue
    if awk -F'\t' '$2 ~ /^\// || $2 ~ /\.\./ { print; found=1 } END { exit !found }' \
         "$TMP/fx-$NAME/imports.tsv" >/dev/null 2>&1; then
      fail "$NAME: an edge escaped the fixture tree"
      LEAK=1
    fi
  done
  [ "$LEAK" -eq 0 ] && [ "$FAM_N" -gt 0 ] && pass "no edge resolves outside the tree it came from"
fi

# --- 17. blast-radius walks importers, not imports -------------------------
BRP="$TMP/brproj"
rm -rf "$BRP"; mkdir -p "$BRP/src/lib" "$BRP/src/api"
printf 'export function verify() { return true }\n' > "$BRP/src/lib/auth.ts"
printf "import { verify } from '../lib/auth'\nexport const login = verify\n" > "$BRP/src/api/login.ts"
printf "import { login } from './login'\nexport const r = login\n" > "$BRP/src/api/routes.ts"
printf 'export const unrelated = 1\n' > "$BRP/src/api/other.ts"
BR="$(sh scripts/blast-radius.sh --root "$BRP" --file src/lib/auth.ts --out "$TMP/brout" 2>&1)"
case "$BR" in
  *"src/api/login.ts"*) pass "blast-radius finds the direct importer" ;;
  *) fail "blast-radius missed the direct importer"; printf '%s\n' "$BR" | head -6 | sed 's/^/        /' ;;
esac
case "$BR" in
  *"src/api/routes.ts"*) pass "blast-radius follows the chain to depth 2" ;;
  *) fail "blast-radius did not reach the transitive importer" ;;
esac
case "$BR" in
  *"src/api/other.ts"*) fail "blast-radius reported an unrelated file" ;;
  *) pass "blast-radius leaves unrelated files out" ;;
esac
# Direction matters: auth.ts must NOT appear as downstream of login.ts.
BR2="$(sh scripts/blast-radius.sh --root "$BRP" --file src/api/routes.ts --out "$TMP/brout" 2>&1)"
case "$BR2" in
  *"Nothing imports the seed"*) pass "blast-radius walks importers, not imports" ;;
  *) fail "blast-radius walked the graph forwards - it reported what the seed imports" ;;
esac
# The report must admit what it cannot see rather than implying completeness.
case "$BR" in
  *"never as a complete one"*) pass "blast-radius states its blind spots" ;;
  *) fail "blast-radius omitted the completeness caveat" ;;
esac

# --- 18. the extractor never invents an edge from a comment or a string ----
TRAP="$TMP/trapproj"
rm -rf "$TRAP"; mkdir -p "$TRAP/src"
printf 'export const real = 1\n' > "$TRAP/src/real.ts"
printf 'export const ghost = 1\n' > "$TRAP/src/ghost.ts"
cat > "$TRAP/src/main.ts" <<'TRAPEOF'
import { real } from './real'
// import { ghost } from './ghost'
/* import { ghost } from './ghost' */
const s = "import { ghost } from './ghost'"
const t = `require('./ghost')`
TRAPEOF
sh scripts/code-graph.sh --root "$TRAP" --out "$TMP/trapout" --quiet >/dev/null 2>&1
if grep -q 'ghost' "$TMP/trapout/imports.tsv" 2>/dev/null; then
  fail "extractor invented an edge from a comment or a string literal"
  grep 'ghost' "$TMP/trapout/imports.tsv" | sed 's/^/        /'
else
  pass "extractor ignores commented-out and quoted imports"
fi
grep -q 'real.ts' "$TMP/trapout/imports.tsv" 2>/dev/null \
  && pass "extractor still finds the real import beside the traps" \
  || fail "extractor missed the real import"

# --- 19. --diff seeds from the working tree, untracked included ------------
DP="$TMP/diffproj"
rm -rf "$DP"; mkdir -p "$DP/src"
( cd "$DP" && git init -q . 2>/dev/null \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null ) || true
printf 'export const a = 1\n' > "$DP/src/a.ts"
printf "import { a } from './a'\nexport const b = a\n" > "$DP/src/b.ts"
if [ -d "$DP/.git" ]; then
  DR="$(sh scripts/blast-radius.sh --root "$DP" --diff --out "$TMP/dout" 2>&1)"
  case "$DR" in
    *"src/b.ts"*) pass "--diff seeds from untracked files and finds their importers" ;;
    *"nothing changed"*) fail "--diff reported nothing changed with untracked files present" ;;
    *) fail "--diff did not trace the changed file" ;;
  esac
else
  note "git unavailable - --diff mode untested"
fi

rm -rf "$TMP" 2>/dev/null

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf 'All checks passed.\n'
else
  printf 'Checks failed.\n'
fi
exit "$FAIL"
