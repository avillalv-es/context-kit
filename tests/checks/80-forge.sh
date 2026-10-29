# Forge: the opt-in CLAUDE.md section, /forge-init and the templates/forge/ docs.
#
# Sourced by scripts/check.sh, which provides pass, fail, note and $TMP. Also
# runnable alone from anywhere:  sh tests/checks/80-forge.sh
# Goes through claude-sections.sh directly, never through a hook.

FG_STANDALONE=0
if ! command -v pass >/dev/null 2>&1; then
  FG_STANDALONE=1
  FAIL=0
  note() { printf '  %s\n' "$1"; }
  fail() { printf 'FAIL  %s\n' "$1"; FAIL=1; }
  pass() { printf 'ok    %s\n' "$1"; }
  cd "$(dirname "$0")/../.." || exit 1
  TMP=$(mktemp -d)
fi

# --- forge --------------------------------------------------------------------
FG_SEC=templates/sections/opt-in/70-forge.md
FG_CMD=commands/forge-init.md
FG_SKILL=skills/forge-init/SKILL.md
FG="$TMP/fg"; mkdir -p "$FG/data" 2>/dev/null
# The developer's own lean level and data dir must not change what is stamped.
fg_cs() { CONTEXT_KIT_LEVEL= CLAUDE_PLUGIN_DATA="$FG/data" sh scripts/claude-sections.sh "$@"; }

# Paid every session once opted in, so the section has a hard size cap.
if [ -f "$FG_SEC" ]; then
  FG_LINES=$(wc -l < "$FG_SEC" | tr -d ' ')
  if [ "$FG_LINES" -le 12 ]; then
    pass "forge section exists and is $FG_LINES lines (cap 12)"
  else
    fail "forge section is $FG_LINES lines, over the 12-line cap"
  fi
else
  fail "missing $FG_SEC"
fi

# Opt-in: stamp never adds it, and status stays silent about it.
printf '# Fresh\n' > "$FG/fresh.md"
FG_OUT=$(fg_cs stamp "$FG/fresh.md" 2>&1)
if ! grep -q 'context-kit:begin forge' "$FG/fresh.md" && ! printf '%s' "$FG_OUT" | grep -q forge; then
  pass "stamp does not add the opt-in forge section"
else
  fail "stamp added or mentioned forge on a repo that did not opt in"
fi
if fg_cs status "$FG/fresh.md" 2>&1 | grep -q ' forge$'; then
  fail "status reports forge on a repo that did not opt in"
else
  pass "status prints nothing for an absent opt-in section"
fi

# on adds it, verbatim, and status then reports it.
fg_cs on forge "$FG/fresh.md" >/dev/null 2>&1
awk '/^<!-- context-kit:begin forge -->/ { f = 1; next }
     /^<!-- context-kit:end forge -->/ { f = 0 }
     f { sub(/\r$/, ""); print }' "$FG/fresh.md" > "$FG/body.txt"
tr -d '\r' < "$FG_SEC" > "$FG/want.txt" 2>/dev/null
if [ -s "$FG/body.txt" ] && cmp -s "$FG/body.txt" "$FG/want.txt"; then
  pass "on forge adds the block, the section template verbatim"
else
  fail "on forge did not add a block equal to $FG_SEC"
fi
if fg_cs status "$FG/fresh.md" 2>&1 | grep -qx 'ok forge'; then
  pass "status reports ok forge once added"
else
  fail "status did not report 'ok forge' after on forge"
fi

# Once present it is kept current like any other section.
cp "$FG/fresh.md" "$FG/old.md"
awk '/^<!-- context-kit:begin forge -->/ { f = 1; print; next }
     f == 1 { print "stale line"; f = 2; next } { print }' "$FG/old.md" > "$FG/stale.md"
FG_OUT=$(fg_cs stamp "$FG/stale.md" 2>&1)
case "$FG_OUT" in
  *"stamped forge (updated)"*) pass "stamp rewrites an outdated forge block" ;;
  *) fail "stamp did not update an outdated forge block: $(printf '%s' "$FG_OUT" | head -c 120)" ;;
esac
if fg_cs status "$FG/stale.md" 2>&1 | grep -qx 'ok forge'; then
  pass "the rewritten forge block is ok again"
else
  fail "forge block is not ok after the rewrite"
fi

# off then on returns it in place; text after the block proves it.
printf '\n## Mine\nkept as written\n' >> "$FG/fresh.md"
cp "$FG/fresh.md" "$FG/fresh.1"
fg_cs off forge "$FG/fresh.md" >/dev/null 2>&1
fg_cs on forge "$FG/fresh.md" >/dev/null 2>&1
if cmp -s "$FG/fresh.md" "$FG/fresh.1"; then
  pass "forge off then on round-trips byte-identically"
else
  fail "forge off then on changed the file"
fi

# The doc set: exactly these files, and nothing from the apps it was drawn from.
FG_WANT="README.md platform.md env-and-secrets.md email-smtp.md sign-in-and-first-admin.md database.md files-backups-scheduler.md rbac.md release-checklists.md troubleshooting.md first-deploy.md app.md"
FG_N=0; FG_MISS=""
for f in $FG_WANT; do [ -f "templates/forge/$f" ] || FG_MISS="$FG_MISS $f"; done
if [ -d templates/forge ]; then
  for f in templates/forge/* templates/forge/.[!.]*; do [ -e "$f" ] && FG_N=$((FG_N + 1)); done
fi
if [ "$FG_N" -eq 12 ] && [ -z "$FG_MISS" ]; then
  pass "templates/forge/ holds exactly the 12 doc files"
else
  fail "templates/forge/ is not exactly the 12 expected files (have $FG_N, missing:$FG_MISS)"
fi
if [ -d templates/forge ] && ! grep -rqiE 'prds|alphapack' templates/forge; then
  pass "templates/forge/ names no source app (prds, alphapack)"
else
  fail "templates/forge/ is missing or mentions prds or alphapack"
fi

# The command hands the work to the script; the skill carries the procedure.
if [ -f "$FG_CMD" ] && grep -q '^description:' "$FG_CMD" && grep -q 'claude-sections\.sh' "$FG_CMD" \
   && grep -q 'forge' "$FG_CMD" && grep -q '\$ARGUMENTS' "$FG_CMD"; then
  pass "/forge-init has a description, calls claude-sections.sh and takes \$ARGUMENTS"
else
  fail "$FG_CMD is missing its description, the claude-sections.sh call, forge or \$ARGUMENTS"
fi
if [ -f "$FG_SKILL" ] && grep -q '^name: forge-init' "$FG_SKILL"; then
  pass "forge-init skill exists with its name"
else
  fail "$FG_SKILL is missing or lacks 'name: forge-init'"
fi

# The skill asks for features, maps each feature file it may copy, and ends in
# plan mode from its adoption prompt; Entra sign-in is in that prompt unasked.
FG_PROMPT=skills/forge-init/references/adopt-prompt.md
FG_MAPOK=1
for f in database.md files-backups-scheduler.md email-smtp.md rbac.md first-deploy.md; do
  grep -q "\`$f\`" "$FG_SKILL" 2>/dev/null || FG_MAPOK=0
done
if [ "$FG_MAPOK" -eq 1 ] && grep -q 'AskUserQuestion' "$FG_SKILL" && grep -q 'EnterPlanMode' "$FG_SKILL" \
   && grep -q 'adopt-prompt.md' "$FG_SKILL"; then
  pass "forge-init asks for features, maps every feature file and plans in plan mode"
else
  fail "$FG_SKILL is missing the feature question, a feature file, EnterPlanMode or adopt-prompt.md"
fi
if [ -f "$FG_PROMPT" ] && grep -q 'JWKS' "$FG_PROMPT" && grep -q 'no client secret' "$FG_PROMPT" \
   && ! grep -qiE 'prds|alphapack' "$FG_PROMPT"; then
  pass "the adoption prompt carries Entra token verification and names no source app"
else
  fail "$FG_PROMPT is missing, lacks the Entra verification steps, or names a source app"
fi

# What the session hook sees: every default section stamped, and no line that is
# not ok or off, so the opt-in section never reads as missing.
printf '# Hook\n' > "$FG/hook.md"
fg_cs stamp "$FG/hook.md" >/dev/null 2>&1
FG_BAD=$(fg_cs status "$FG/hook.md" 2>&1 | grep -vE '^(ok|off) ')
if [ -z "$FG_BAD" ] && fg_cs status "$FG/hook.md" 2>&1 | grep -q '^ok '; then
  pass "a fully stamped file shows no non-ok line, opt-in sections included"
else
  fail "status of a fully stamped file has a non-ok line: $(printf '%s' "$FG_BAD" | head -c 120)"
fi

if [ "$FG_STANDALONE" -eq 1 ]; then
  printf '\n'
  if [ "$FAIL" -eq 0 ]; then
    printf 'forge checks passed.\n'
  else
    printf 'forge checks FAILED.\n'
  fi
  exit "$FAIL"
fi
