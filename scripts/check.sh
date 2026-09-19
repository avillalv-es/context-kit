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
# A read outside the project is not ours to record.
printf '%s' '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"/etc/passwd"}}' \
  | CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$TMP/data" CLAUDE_PROJECT_DIR="$TMP/proj" sh hooks/context-kit.sh event >/dev/null 2>&1
if grep -q 'passwd' "$TMP/data/events/"*.tsv 2>/dev/null; then
  fail "hook event recorded a file outside the project"
else
  pass "hook event ignores files outside the project"
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

# --- 9. the sh and ps1 twins handle the same actions -----------------------
# They are registered for the same events, so an action one of them silently
# drops is a feature that exists on Linux and not on Windows.
PARITY=0
for A in session subagent mode signal event; do
  grep -q "^  $A)" hooks/context-kit.sh 2>/dev/null || { fail "sh hook does not handle '$A'"; PARITY=1; }
  grep -q "'$A'" hooks/context-kit.ps1 2>/dev/null || { fail "ps1 hook does not handle '$A'"; PARITY=1; }
done
[ "$PARITY" -eq 0 ] && pass "sh and ps1 hooks handle the same actions"

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
