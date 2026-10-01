# Context sync: scripts/context-sync.sh on scratch git repos, the findings.sh
# staleness check it leans on, and the size budgets of the files that load
# every session.
#
# Sourced by scripts/check.sh, which supplies pass, fail, note and $TMP and
# starts in the repo root. Also runs alone:  sh tests/checks/40-context-sync.sh

if ! type pass >/dev/null 2>&1; then
  SY_ALONE=1
  FAIL=0
  note() { printf '  %s\n' "$1"; }
  fail() { printf 'FAIL  %s\n' "$1"; FAIL=1; }
  pass() { printf 'ok    %s\n' "$1"; }
  cd "$(dirname "$0")/../.." || exit 1
  TMP="$(mktemp -d)"
else
  SY_ALONE=0
fi

SY_PLUGIN="$PWD"
SY_W="$TMP/sy"
SY_DATA="$SY_W/data"
SY_R="$SY_W/repo"
mkdir -p "$SY_DATA" "$SY_R"

# Run the script against the scratch repo with nothing leaking in from the
# environment this suite runs in.
sy() {
  CLAUDE_PLUGIN_ROOT="$SY_PLUGIN" CLAUDE_PLUGIN_DATA="$SY_DATA" CLAUDE_PROJECT_DIR="$SY_R" \
    sh "$SY_PLUGIN/scripts/context-sync.sh" "$@" --root "$SY_R" 2>&1
}
sy_git() { git -C "$SY_R" -c user.email=t@t -c user.name=t -c core.autocrlf=false "$@"; }

# sy_has OUTPUT LINE MESSAGE: LINE must be a whole line of OUTPUT.
sy_has() {
  if printf '%s\n' "$1" | grep -Fxq -- "$2"; then pass "$3"
  else fail "$3 (wanted the line: $2)"; printf '%s\n' "$1" | head -8 | sed 's/^/        /'; fi
}
# sy_lacks OUTPUT TEXT MESSAGE: TEXT must appear nowhere in OUTPUT.
sy_lacks() {
  if printf '%s\n' "$1" | grep -Fq -- "$2"; then
    fail "$3 (found: $2)"; printf '%s\n' "$1" | head -8 | sed 's/^/        /'
  else pass "$3"; fi
}
# sy_silent OUTPUT MESSAGE: OUTPUT must be empty.
sy_silent() {
  if [ -z "$1" ]; then pass "$2"
  else fail "$2"; printf '%s\n' "$1" | head -8 | sed 's/^/        /'; fi
}

# --- no layout at all ------------------------------------------------------------
SY_E="$SY_W/empty"
mkdir -p "$SY_E"
git -C "$SY_E" init -q
printf '# notes\n' > "$SY_E/NOTES.md"
OUT="$(CLAUDE_PLUGIN_ROOT="$SY_PLUGIN" sh "$SY_PLUGIN/scripts/context-sync.sh" check --root "$SY_E" 2>&1)"
if [ "$OUT" = "layout missing" ]; then
  pass "check says only 'layout missing' when none of the four folders exists"
else
  fail "check on a repo with no layout printed: $OUT"
fi

# --- not a git repo at all -----------------------------------------------------------
SY_N="$SY_W/nogit"
mkdir -p "$SY_N/knowledge"
printf '# notes\n' > "$SY_N/NOTES.md"
OUT="$(CLAUDE_PLUGIN_ROOT="$SY_PLUGIN" sh "$SY_PLUGIN/scripts/context-sync.sh" check --root "$SY_N" 2>&1)"
sy_has "$OUT" "source new NOTES.md" "check works in a directory that is not a git repo"

# --- the scratch project -----------------------------------------------------------
git -C "$SY_R" init -q
mkdir -p "$SY_R/knowledge" "$SY_R/findings" "$SY_R/.claude/rules" "$SY_R/docs" \
         "$SY_R/node_modules" "$SY_R/vendor" "$SY_R/build" "$SY_R/.github" "$SY_R/sub"
printf '# Knowledge index\n' > "$SY_R/knowledge/INDEX.md"
: > "$SY_R/findings/.gitkeep"
: > "$SY_R/.claude/rules/.gitkeep"
printf '# Progress\n\nold status line\n' > "$SY_R/PROGRESS.md"
printf '# Ideas\n\nold idea line\n' > "$SY_R/docs/IDEAS.md"
printf 'x\n' > "$SY_R/node_modules/x.md"
printf 'x\n' > "$SY_R/vendor/v.md"
printf 'x\n' > "$SY_R/build/b.md"
printf 'x\n' > "$SY_R/.github/h.md"
printf 'x\n' > "$SY_R/sub/other.md"
printf '# Scratch\n' > "$SY_R/CLAUDE.md"
printf 'x\n' > "$SY_R/CLAUDE.local.md"
sy_git add -A
sy_git commit -qm init

OUT="$(sy check)"
sy_has "$OUT" "source new PROGRESS.md" "check lists a root markdown file as a new source"
sy_has "$OUT" "source new docs/IDEAS.md" "check lists a docs/ markdown file as a new source"
for X in node_modules/x.md vendor/v.md build/b.md .github/h.md sub/other.md CLAUDE.md CLAUDE.local.md; do
  sy_lacks "$OUT" "$X" "check does not treat $X as a source"
done
sy_has "$OUT" "sections missing context-sync" "check reports a managed section CLAUDE.md lacks"

# Make CLAUDE.md current so the sections lines stop, then record everything.
sh "$SY_PLUGIN/scripts/claude-sections.sh" stamp "$SY_R/CLAUDE.md" >/dev/null 2>&1
if grep -q 'context-kit:begin context-sync' "$SY_R/CLAUDE.md"; then
  pass "claude-sections.sh stamps the context-sync section into CLAUDE.md"
else
  fail "the stamped CLAUDE.md has no context-sync section"
fi
sy mark --all >/dev/null
sy_silent "$(sy check)" "mark --all leaves check with nothing to say"
SY_LED="$SY_R/.claude/context-sync.tsv"
if [ "$(grep -c '^source' "$SY_LED")" -eq 2 ] \
   && [ "$(awk -F'\t' '$1 == "source" && NF != 5' "$SY_LED" | wc -l | tr -d ' ')" -eq 0 ]; then
  pass "the ledger holds one five-column row per source"
else
  fail "the ledger rows are not kind, path, blob, commit, date"; sed 's/^/        /' "$SY_LED"
fi

# --- an edit, and a diff that shows only the edit ---------------------------------
printf 'appended ALPHA line\n' >> "$SY_R/PROGRESS.md"
OUT="$(sy check)"
sy_has "$OUT" "source changed PROGRESS.md" "check sees an appended line"
DF="$(sy diff PROGRESS.md)"
sy_has "$DF" "+appended ALPHA line" "diff shows the appended line"
sy_lacks "$DF" "old status line" "diff leaves out what was already there"
sy_git add -A
sy_git commit -qm "progress"
sy mark PROGRESS.md >/dev/null
sy_silent "$(sy check)" "mark PATH silences that path"

# --- an uncommitted, brand-new file -------------------------------------------------
printf '# New\n\nfirst line\n' > "$SY_R/docs/NEW.md"
sy_has "$(sy check)" "source new docs/NEW.md" "check sees an uncommitted new file"
sy mark docs/NEW.md >/dev/null
printf 'second line\n' >> "$SY_R/docs/NEW.md"
sy_has "$(sy check)" "source changed docs/NEW.md" "check sees an edit to a file that was untracked when marked"
DF="$(sy diff docs/NEW.md)"
sy_has "$DF" "second line" "diff of a file that was not in git still shows the new line"
case "$DF" in
  *"whole file follows"*) pass "diff says so when it falls back to the whole file" ;;
  *) fail "diff did not explain the whole-file fallback"; printf '%s\n' "$DF" | head -5 | sed 's/^/        /' ;;
esac
sy mark docs/NEW.md >/dev/null

# --- removal -------------------------------------------------------------------------
rm -f "$SY_R/docs/NEW.md"
sy_has "$(sy check)" "source gone docs/NEW.md" "check sees a marked, untracked source removed"
sy mark docs/NEW.md >/dev/null
sy_silent "$(sy check)" "marking a gone path drops its row"
if grep -q 'docs/NEW.md' "$SY_LED"; then fail "the ledger still has the row for a removed file"; else pass "the removed file left the ledger"; fi

rm -f "$SY_R/docs/IDEAS.md"
sy_has "$(sy check)" "source gone docs/IDEAS.md" "check sees a tracked source deleted from the work tree"
sy_git checkout -- docs/IDEAS.md
sy_silent "$(sy check)" "restoring the file makes it current again (the blob is compared, not the mtime)"

# marking something that is not a source must not put it in the ledger
sy mark CLAUDE.md >/dev/null
if grep -q 'CLAUDE.md' "$SY_LED"; then fail "mark recorded CLAUDE.md, which is never a source"; else pass "mark ignores a path that is not a source"; fi

# --- sources add -------------------------------------------------------------------
mkdir -p "$SY_R/notes" "$SY_R/docs/sub"
printf '# a\n' > "$SY_R/notes/a.md"
printf '# deep\n' > "$SY_R/docs/sub/deep.md"
OUT="$(sy check)"
sy_lacks "$OUT" "notes/a.md" "a path outside the default globs is not a source"
sy_has "$OUT" "source new docs/sub/deep.md" "docs/**/*.md reaches below docs/"
sy mark docs/sub/deep.md >/dev/null
printf '# spaced\n' > "$SY_R/docs/My Notes.md"
sy_has "$(sy check)" "source new docs/My Notes.md" "a path with a space is listed whole"
sy mark "docs/My Notes.md" >/dev/null
sy_silent "$(sy check)" "a path with a space can be marked"
sy sources add 'notes/*.md' >/dev/null
sy_has "$(sy check)" "source new notes/a.md" "sources add makes the new glob count"
if sy sources list | grep -Fxq "extra notes/*.md"; then pass "sources list shows the added glob"; else fail "sources list lost the added glob"; fi
case "$(sy sources add 'notes/*.md')" in
  "already a source glob"*) pass "adding the same glob twice is a no-op" ;;
  *) fail "adding the same glob twice did something" ;;
esac
sy mark notes/a.md >/dev/null
if head -1 "$SY_LED" | grep -q '^#sources'; then pass "the extra glob persists in the ledger header"; else fail "the ledger header lost the glob after a mark"; fi
sy_silent "$(sy check)" "everything marked: check is silent again"

# --- findings ------------------------------------------------------------------------
printf '# probe\n\n## 2026-09-01 - q\n\n**Question:** q\n\n**Finding:** f\n\n**Outcome:** useful\n\n**Sources:** a.py\n' > "$SY_R/findings/probe.md"
printf '## 2026-09-02 - readme\n\n**Question:** README_ONLY_QUESTION\n\n**Finding:** f\n\n**Outcome:** useful\n\n**Sources:** README_ONLY_MARKER.py\n' > "$SY_R/findings/README.md"
OUT="$(sy check)"
sy_has "$OUT" "findings changed findings/probe.md" "check lists a new findings log"
sy_has "$OUT" "findings lessons-stale" "check reports LESSONS.md missing while entries exist"
sy_lacks "$OUT" "findings/README.md" "check never offers findings/README.md for promotion"
sh "$SY_PLUGIN/scripts/findings.sh" reflect --root "$SY_R" >/dev/null 2>&1
OUT="$(sy check)"
sy_lacks "$OUT" "lessons-stale" "reflect clears the stale line"
sy_lacks "$OUT" "findings/LESSONS.md" "check never offers the generated LESSONS.md"
sy mark findings/probe.md >/dev/null
sy_silent "$(sy check)" "mark silences a findings log"
if grep -q 'README_ONLY_MARKER' "$SY_R/findings/LESSONS.md"; then
  fail "findings.sh reflect read findings/README.md as a log"
else
  pass "findings.sh reflect ignores findings/README.md"
fi
printf '\n## 2026-09-03 - more\n\n**Question:** q2\n\n**Finding:** f\n\n**Outcome:** dead_end\n\n**Sources:** b.py\n' >> "$SY_R/findings/probe.md"
touch -t 202001010000 "$SY_R/findings/LESSONS.md"
OUT="$(sy check)"
sy_has "$OUT" "findings changed findings/probe.md" "check sees an appended findings entry"
sy_has "$OUT" "findings lessons-stale" "check reports LESSONS.md older than an entry"
sh "$SY_PLUGIN/scripts/findings.sh" reflect --if-stale --root "$SY_R" >/dev/null 2>&1
sy mark findings/probe.md >/dev/null
sy_silent "$(sy check)" "reflect --if-stale plus mark leaves nothing"

SY_F2="$SY_W/f2"
mkdir -p "$SY_F2/findings"
printf '# readme only\n' > "$SY_F2/findings/README.md"
sh "$SY_PLUGIN/scripts/findings.sh" reflect --root "$SY_F2" >/dev/null 2>&1
SY_RC=$?
if [ "$SY_RC" -eq 2 ]; then pass "reflect treats a findings/ holding only README.md as empty"; else fail "reflect on a README-only findings/ exited $SY_RC, not 2"; fi
sh "$SY_PLUGIN/scripts/findings.sh" reflect --check --root "$SY_F2" >/dev/null 2>&1
SY_RC=$?
if [ "$SY_RC" -eq 0 ]; then pass "reflect --check exits 0 when there are no entries"; else fail "reflect --check with no entries exited $SY_RC"; fi
printf '## 2026-09-01 - q\n\n**Question:** q\n\n**Outcome:** useful\n' > "$SY_F2/findings/a.md"
sh "$SY_PLUGIN/scripts/findings.sh" reflect --check --root "$SY_F2" >/dev/null 2>&1
SY_RC=$?
if [ "$SY_RC" -eq 3 ]; then pass "reflect --check exits 3 when LESSONS.md is missing"; else fail "reflect --check exited $SY_RC, not 3, with no LESSONS.md"; fi
sh "$SY_PLUGIN/scripts/findings.sh" reflect --root "$SY_F2" >/dev/null 2>&1
sh "$SY_PLUGIN/scripts/findings.sh" reflect --check --root "$SY_F2" >/dev/null 2>&1
SY_RC=$?
if [ "$SY_RC" -eq 0 ]; then pass "reflect --check exits 0 once LESSONS.md is current"; else fail "reflect --check exited $SY_RC on a current LESSONS.md"; fi

# --- the index -----------------------------------------------------------------------
printf '# foo\n' > "$SY_R/knowledge/foo.md"
printf '# oo\n' > "$SY_R/knowledge/oo.md"
sy_has "$(sy check)" "index missing knowledge/foo.md" "check sees a knowledge file with no INDEX row"
printf '\n| [`foo.md`](foo.md) | Read it when changing foo |\n' >> "$SY_R/knowledge/INDEX.md"
OUT="$(sy check)"
sy_lacks "$OUT" "knowledge/foo.md" "a row naming the file clears it"
sy_has "$OUT" "index missing knowledge/oo.md" "a row for foo.md does not count as a row for oo.md"
rm -f "$SY_R/knowledge/oo.md"

# --- rules ---------------------------------------------------------------------------
printf -- '---\ndescription: d\n---\n# R\n' > "$SY_R/.claude/rules/r1.md"
printf '# R3 has no frontmatter\n' > "$SY_R/.claude/rules/r3.md"
printf -- '---\ndescription: d\npaths:\n  - "src/**"\n---\n# R\n' > "$SY_R/.claude/rules/r2.md"
OUT="$(sy check)"
sy_has "$OUT" "rule no-paths .claude/rules/r1.md" "check flags a rule with frontmatter but no paths"
sy_has "$OUT" "rule no-paths .claude/rules/r3.md" "check flags a rule with no frontmatter"
sy_lacks "$OUT" ".claude/rules/r2.md" "check accepts a rule with a paths list"
printf -- '---\ndescription: d\npaths: ["src/**"]\n---\n# R\n' > "$SY_R/.claude/rules/r1.md"
rm -f "$SY_R/.claude/rules/r3.md"
sy_silent "$(sy check)" "an inline paths list counts, and fixed rules go quiet"

# --- skills --------------------------------------------------------------------------
mkdir -p "$SY_R/.claude/skills/s1" "$SY_R/.claude/skills/s2"
printf -- '---\nname: s1\ndescription: Helps with stuff.\n---\n# S1\n' > "$SY_R/.claude/skills/s1/SKILL.md"
printf -- '---\nname: s2\ndescription: >\n  Use when deploying the thing.\n---\n# S2\n' > "$SY_R/.claude/skills/s2/SKILL.md"
OUT="$(sy check)"
sy_has "$OUT" "skill no-trigger .claude/skills/s1/SKILL.md" "check flags a skill whose description is not a trigger"
sy_lacks "$OUT" "skill no-trigger .claude/skills/s2/SKILL.md" "check reads a description that continues on the next line"
sy_has "$OUT" "index missing .claude/skills/s1/SKILL.md" "check flags a project skill with no INDEX row"
printf -- '---\nname: s1\ndescription: Use when s1 comes up.\n---\n# S1\n' > "$SY_R/.claude/skills/s1/SKILL.md"
printf '\n| `.claude/skills/s1/SKILL.md` | Read it when s1 comes up |\n| `s2` skill | Read it when deploying |\n' >> "$SY_R/knowledge/INDEX.md"
sy_silent "$(sy check)" "a trigger description and an INDEX row clear a skill"

# --- CLAUDE.md sections ----------------------------------------------------------------
printf '# Scratch\n\n## Context layout\n\nThis project uses a three-tier layout.\n\nTo reorganize any of it, run `/context-init`.\n' > "$SY_R/CLAUDE.md"
OUT="$(sy check)"
sy_has "$OUT" "sections legacy context-layout" "check reports a 0.4.x CLAUDE.md block as legacy"
sy_has "$OUT" "sections missing context-sync" "check reports a section a legacy CLAUDE.md lacks"
sh "$SY_PLUGIN/scripts/claude-sections.sh" stamp "$SY_R/CLAUDE.md" >/dev/null 2>&1
sh "$SY_PLUGIN/scripts/claude-sections.sh" off context-sync "$SY_R/CLAUDE.md" >/dev/null 2>&1
sy_silent "$(sy check)" "a section turned off is not reported"
sh "$SY_PLUGIN/scripts/claude-sections.sh" on context-sync "$SY_R/CLAUDE.md" >/dev/null 2>&1

# --- everything fixed and marked ---------------------------------------------------------
sy mark --all >/dev/null
sy_silent "$(sy check)" "with everything marked and fixed, check prints exactly nothing"

# --- the files that load every session stay small ----------------------------------------
SY_SEC="templates/sections/40-context-sync.md"
SY_SK="skills/context-sync/SKILL.md"
if [ -f "$SY_SEC" ] && [ "$(wc -l < "$SY_SEC" | tr -d ' ')" -le 12 ]; then
  pass "the context-sync CLAUDE.md section is 12 lines or fewer"
else
  fail "$SY_SEC is missing or longer than 12 lines"
fi
if [ -f "$SY_SK" ]; then
  SY_BODY="$(awk '/^---[ \t]*$/ { n++; next } n >= 2 { c++ } END { print c + 0 }' "$SY_SK")"
  if [ "$SY_BODY" -le 45 ]; then
    pass "the context-sync SKILL.md body is 45 lines or fewer ($SY_BODY)"
  else
    fail "the context-sync SKILL.md body is $SY_BODY lines; it loads every session, keep it to 45"
  fi
  if sed -n '/^description:/,/^[a-z-]*:/p' "$SY_SK" | grep -q 'Use when'; then
    pass "the context-sync skill description is written as a trigger"
  else
    fail "the context-sync skill description has no 'Use when'"
  fi
else
  fail "missing $SY_SK"
fi
for SY_F in skills/context-sync/references/routing.md commands/context-sync.md; do
  [ -f "$SY_F" ] || fail "missing $SY_F"
done

if [ "$SY_ALONE" -eq 1 ]; then
  printf '\n'
  if [ "$FAIL" -eq 0 ]; then printf 'All context-sync checks passed.\n'; else printf 'Context-sync checks failed.\n'; fi
  printf 'scratch left in %s\n' "$TMP"
  exit "$FAIL"
fi
