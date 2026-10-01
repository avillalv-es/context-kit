# Model routing: the CLAUDE.md section and /model-routing.
#
# Sourced by scripts/check.sh, which provides pass, fail, note and $TMP. Also
# runnable alone from anywhere:  sh tests/checks/30-model-routing.sh
# Goes through claude-sections.sh directly, never through a hook.

MR_STANDALONE=0
if ! command -v pass >/dev/null 2>&1; then
  MR_STANDALONE=1
  FAIL=0
  note() { printf '  %s\n' "$1"; }
  fail() { printf 'FAIL  %s\n' "$1"; FAIL=1; }
  pass() { printf 'ok    %s\n' "$1"; }
  cd "$(dirname "$0")/../.." || exit 1
  TMP=$(mktemp -d)
fi

# --- model routing ------------------------------------------------------------
MR_SEC=templates/sections/30-model-routing.md
MR_CMD=commands/model-routing.md
MR="$TMP/mr"; mkdir -p "$MR/data" 2>/dev/null
# The developer's own lean level and data dir must not change what is stamped.
mr_cs() { CONTEXT_KIT_LEVEL= CLAUDE_PLUGIN_DATA="$MR/data" sh scripts/claude-sections.sh "$@"; }

# Paid every session, so the section has a hard size cap.
if [ -f "$MR_SEC" ]; then
  MR_LINES=$(wc -l < "$MR_SEC" | tr -d ' ')
  if [ "$MR_LINES" -le 12 ]; then
    pass "model-routing section exists and is $MR_LINES lines (cap 12)"
  else
    fail "model-routing section is $MR_LINES lines, over the 12-line cap"
  fi
else
  fail "missing $MR_SEC"
fi

# Stamp: a title-only file gains the section, wrapped in markers.
printf '# Fresh\n' > "$MR/fresh.md"
MR_OUT=$(mr_cs stamp "$MR/fresh.md" 2>&1)
case "$MR_OUT" in
  *"stamped model-routing (added)"*) pass "stamp adds model-routing to a title-only file" ;;
  *) fail "stamp did not add model-routing: $(printf '%s' "$MR_OUT" | head -c 120)" ;;
esac

# Verbatim: the text between the markers is the template, byte for byte.
awk '/^<!-- context-kit:begin model-routing -->/ { f = 1; next }
     /^<!-- context-kit:end model-routing -->/ { f = 0 }
     f { sub(/\r$/, ""); print }' "$MR/fresh.md" > "$MR/body.txt"
tr -d '\r' < "$MR_SEC" > "$MR/want.txt"
if [ -s "$MR/body.txt" ] && cmp -s "$MR/body.txt" "$MR/want.txt"; then
  pass "stamped block is the section template verbatim"
else
  fail "stamped model-routing block differs from $MR_SEC"
fi

# Status after stamping.
if mr_cs status "$MR/fresh.md" 2>&1 | grep -qx 'ok model-routing'; then
  pass "status reports ok model-routing after stamping"
else
  fail "status did not report 'ok model-routing' after stamping"
fi

# off then on puts the block back exactly where it was. Text after the block
# proves it returns in place instead of at the end of the file.
printf '\n## Mine\nkept as written\n' >> "$MR/fresh.md"
cp "$MR/fresh.md" "$MR/fresh.1"
mr_cs off model-routing "$MR/fresh.md" >/dev/null 2>&1
if grep -qx '<!-- context-kit:off model-routing -->' "$MR/fresh.md" && ! grep -q '^## Model routing' "$MR/fresh.md"; then
  pass "off replaces the block with the off marker"
else
  fail "off did not reduce model-routing to its marker line"
fi
mr_cs on model-routing "$MR/fresh.md" >/dev/null 2>&1
if cmp -s "$MR/fresh.md" "$MR/fresh.1"; then
  pass "off then on round-trips byte-identically"
else
  fail "off then on changed the file"
fi

# The command file hands the work to the script and passes the argument on.
if [ -f "$MR_CMD" ] && grep -q '^description:' "$MR_CMD" && grep -q 'claude-sections\.sh' "$MR_CMD" \
   && grep -q 'model-routing' "$MR_CMD" && grep -q '\$ARGUMENTS' "$MR_CMD"; then
  pass "/model-routing has a description, calls claude-sections.sh and takes \$ARGUMENTS"
else
  fail "$MR_CMD is missing its description, the claude-sections.sh call or \$ARGUMENTS"
fi

# The lean-execution skill points at the routing rule.
if grep -q 'model: "sonnet"' skills/lean-execution/SKILL.md && grep -q '/model-routing' skills/lean-execution/SKILL.md; then
  pass "lean-execution skill names the Sonnet model choice and /model-routing"
else
  fail "lean-execution skill does not mention model: \"sonnet\" and /model-routing"
fi

if [ "$MR_STANDALONE" -eq 1 ]; then
  printf '\n'
  if [ "$FAIL" -eq 0 ]; then
    printf 'model-routing checks passed.\n'
  else
    printf 'model-routing checks FAILED.\n'
  fi
  exit "$FAIL"
fi
