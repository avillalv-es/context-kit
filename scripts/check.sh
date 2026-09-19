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
for ACTION in session subagent mode signal bogus; do
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
for f in hooks/context-kit.sh hooks/context-kit.ps1 hooks/rules.md knowledge/platform-native.md; do
  [ -f "$f" ] || fail "missing $f"
done
pass "referenced hook files present"

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf 'All checks passed.\n'
else
  printf 'Checks failed.\n'
fi
exit "$FAIL"
