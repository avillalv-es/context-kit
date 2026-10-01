# PR train: the CLAUDE.md section, the handoff template, the skill and the
# command. Sourced by scripts/check.sh, which provides pass, fail, note and
# $TMP; also runnable alone with `sh tests/checks/50-pr-train.sh`.

PT_ALONE=0
if ! command -v pass >/dev/null 2>&1; then
  PT_ALONE=1
  FAIL=0
  note() { printf '  %s\n' "$1"; }
  fail() { printf 'FAIL  %s\n' "$1"; FAIL=1; }
  pass() { printf 'ok    %s\n' "$1"; }
  cd "$(dirname "$0")/../.." || exit 1
  TMP="$(mktemp -d)" || exit 1
fi

PT_SEC=templates/sections/50-pr-train.md
PT_HAND=templates/handoff.md
PT_SKILL=skills/pr-train/SKILL.md
PT_CMD=commands/pr-train.md
PT_DIR="$TMP/pr-train"
mkdir -p "$PT_DIR/data" 2>/dev/null

# contains FILE TEXT: fixed-string match
pt_has() { grep -qF -- "$2" "$1"; }

# --- the CLAUDE.md section ----------------------------------------------------
if [ ! -f "$PT_SEC" ]; then
  fail "$PT_SEC is missing"
else
  PT_N=$(wc -l < "$PT_SEC" | tr -d ' ')
  if [ "$PT_N" -le 14 ]; then pass "pr-train section is $PT_N lines (cap 14)"
  else fail "pr-train section is $PT_N lines; it loads every session, so keep it to 14"; fi

  PT_MISS=""
  for pt_t in '/compact' '.claude/handoff/' 'status: active' '`pr-train`' '/pr-train off'; do
    pt_has "$PT_SEC" "$pt_t" || PT_MISS="$PT_MISS $pt_t"
  done
  if [ -z "$PT_MISS" ]; then pass "pr-train section names /compact, the handoff dir, status: active, the skill and the off switch"
  else fail "pr-train section is missing:$PT_MISS"; fi
fi

# --- stamping through claude-sections.sh --------------------------------------
PT_MD="$PT_DIR/CLAUDE.md"
printf '# Scratch project\n' > "$PT_MD"
pt_run() { CLAUDE_PLUGIN_ROOT="$PWD" CLAUDE_PLUGIN_DATA="$PT_DIR/data" sh scripts/claude-sections.sh "$@"; }

pt_run stamp "$PT_MD" >/dev/null 2>&1
if grep -q '^<!-- context-kit:begin pr-train -->$' "$PT_MD" \
   && grep -q '^<!-- context-kit:end pr-train -->$' "$PT_MD" \
   && grep -q '^## PR train$' "$PT_MD"; then
  pass "stamp adds the pr-train section to a title-only CLAUDE.md"
else
  fail "stamp did not add a marked pr-train section"
fi

case "$(pt_run status "$PT_MD" 2>/dev/null | grep ' pr-train$')" in
  "ok pr-train") pass "status reports pr-train ok after stamping" ;;
  *) fail "status does not report pr-train ok after stamping" ;;
esac

cp "$PT_MD" "$PT_DIR/stamped.md"
pt_run off pr-train "$PT_MD" >/dev/null 2>&1
if grep -q '^<!-- context-kit:off pr-train -->$' "$PT_MD" && ! grep -q 'context-kit:begin pr-train' "$PT_MD"; then
  pass "off collapses pr-train to a single marker line"
else
  fail "off did not collapse pr-train"
fi
pt_run stamp "$PT_MD" >/dev/null 2>&1
if grep -q 'context-kit:begin pr-train' "$PT_MD"; then
  fail "stamp re-added pr-train after it was turned off"
else
  pass "stamp leaves a turned-off pr-train alone"
fi
pt_run on pr-train "$PT_MD" >/dev/null 2>&1
if cmp -s "$PT_MD" "$PT_DIR/stamped.md"; then
  pass "off then on restores CLAUDE.md byte for byte"
else
  fail "off then on changed CLAUDE.md"
fi

# --- the handoff template -----------------------------------------------------
if [ ! -f "$PT_HAND" ]; then
  fail "$PT_HAND is missing"
else
  # The front matter is the block between the first two --- lines.
  PT_FM=$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f' "$PT_HAND")
  PT_MISS=""
  for pt_k in status plan base strategy updated; do
    printf '%s\n' "$PT_FM" | grep -q "^$pt_k:" || PT_MISS="$PT_MISS $pt_k"
  done
  if [ -z "$PT_MISS" ]; then pass "handoff template front matter has status, plan, base, strategy, updated"
  else fail "handoff template front matter is missing:$PT_MISS"; fi

  PT_MISS=""
  for pt_h in '## Goal' '## Repo conventions' '## Tasks' '## Shared files' '## Done log' '## In progress' '## Open questions'; do
    grep -q "^$pt_h" "$PT_HAND" || PT_MISS="$PT_MISS [$pt_h]"
  done
  if [ -z "$PT_MISS" ]; then pass "handoff template has Tasks, Shared files, Done log and In progress sections"
  else fail "handoff template is missing headings:$PT_MISS"; fi
fi

# --- the skill ------------------------------------------------------------------
if [ ! -f "$PT_SKILL" ]; then
  fail "$PT_SKILL is missing"
else
  PT_DESC=$(sed -n 's/^description:[[:space:]]*//p' "$PT_SKILL" | head -1)
  case "$PT_DESC" in
    "Use when "*) pass "pr-train skill description is a one-line trigger starting Use when" ;;
    *) fail "pr-train skill description must start with \"Use when\"" ;;
  esac

  # Body = everything after the closing --- of the front matter.
  PT_BODY=$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {f=0; b=1; next} b' "$PT_SKILL" | wc -l | tr -d ' ')
  if [ "$PT_BODY" -le 110 ]; then pass "pr-train skill body is $PT_BODY lines"
  elif [ -d skills/pr-train/references ]; then pass "pr-train skill body is $PT_BODY lines, with references/ beside it"
  else fail "pr-train skill body is $PT_BODY lines and has no references/ dir"; fi

  PT_MISS=""
  for pt_t in 'isolation' 'worktree' '/compact' 'model: "sonnet"' 'status: complete' 'git status' 'gh pr list' 'Closes #n'; do
    pt_has "$PT_SKILL" "$pt_t" || PT_MISS="$PT_MISS [$pt_t]"
  done
  if [ -z "$PT_MISS" ]; then pass "pr-train skill covers worktree isolation, /compact, model routing, resume and finish"
  else fail "pr-train skill is missing:$PT_MISS"; fi

  if grep -F '.gitignore' "$PT_SKILL" | grep -qF 'containing `*`'; then
    pass "pr-train skill makes the handoff dir ignore itself (.gitignore containing *)"
  else
    fail "pr-train skill does not say the handoff dir gets a .gitignore containing *"
  fi

  if grep -qF 'push the branch in its own command' "$PT_SKILL" || grep -qF 'Push the branch in its own command' "$PT_SKILL"; then
    pass "pr-train skill keeps push in its own command"
  else
    fail "pr-train skill does not say to push in its own command"
  fi

  # Every file the skill points at must exist.
  PT_MISS=""
  for pt_r in $(grep -o 'references/[A-Za-z0-9._-]*\.md' "$PT_SKILL" | sort -u); do
    [ -f "skills/pr-train/$pt_r" ] || PT_MISS="$PT_MISS $pt_r"
  done
  if [ -z "$PT_MISS" ]; then pass "every references/ file the pr-train skill names exists"
  else fail "pr-train skill names missing files:$PT_MISS"; fi
fi

# --- the command ----------------------------------------------------------------
if [ ! -f "$PT_CMD" ]; then
  fail "$PT_CMD is missing"
else
  if pt_has "$PT_CMD" 'claude-sections.sh' && pt_has "$PT_CMD" 'off pr-train' && pt_has "$PT_CMD" 'on pr-train' \
     && pt_has "$PT_CMD" '$ARGUMENTS' && pt_has "$PT_CMD" 'pr-train` skill'; then
    pass "pr-train command hands off to the skill and toggles the section through claude-sections.sh"
  else
    fail "pr-train command must use the skill, \$ARGUMENTS, and claude-sections.sh on|off pr-train"
  fi
fi

if [ "$PT_ALONE" -eq 1 ]; then
  printf '\n'
  if [ "$FAIL" -eq 0 ]; then printf 'pr-train checks passed.\n'; else printf 'pr-train checks failed.\n'; fi
  exit "$FAIL"
fi
