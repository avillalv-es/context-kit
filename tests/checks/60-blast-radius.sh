# blast-radius: the output contract, symbol seeding, --diff, and the CLAUDE.md
# section. Sourced by scripts/check.sh (which provides pass, fail, note and
# $TMP); also runnable on its own:  sh tests/checks/60-blast-radius.sh
#
# Every scenario runs in a scratch git repo under $TMP, so nothing here depends
# on the state of this repository.

if ! command -v pass >/dev/null 2>&1; then
  BT_STANDALONE=1
  FAIL=0
  note() { printf '  %s\n' "$1"; }
  fail() { printf 'FAIL  %s\n' "$1"; FAIL=1; }
  pass() { printf 'ok    %s\n' "$1"; }
  cd "$(dirname "$0")/../.." || exit 1
  TMP="$(mktemp -d)"
  note "scratch repos under $TMP"
else
  BT_STANDALONE=0
fi

BT="$TMP/br60"
mkdir -p "$BT"

# --- helpers ---------------------------------------------------------------------
# Runs blast-radius.sh; the combined output is BT_OUT and the exit status BT_RC.
bt_run() { BT_OUT="$(sh scripts/blast-radius.sh "$@" 2>&1)"; BT_RC=$?; }

# The lines of one `## ` section: from its header to the next blank line.
bt_sect() {
  printf '%s\n' "$1" | awk -v h="## $2" '$0 == h { on = 1; next } on && !NF { on = 0 } /^## / { on = 0 } on'
}

# The seed paths alone: without notes and without the [tag] markers.
bt_seeds() { bt_sect "$1" Seeds | grep -v -e '^note:' -e '^ ' | sed 's/   \[.*$//'; }

# bt_in OUTPUT SECTION NEEDLE: is NEEDLE a substring of a line in that section?
bt_in() { bt_sect "$1" "$2" | grep -qF -e "$3"; }

bt_git() { ( cd "$1" && shift && git "$@" ) >/dev/null 2>&1; }

bt_write() { # bt_write DIR PATH <<content
  mkdir -p "$(dirname "$1/$2")"
  cat > "$1/$2"
}

# --- the fixture -------------------------------------------------------------------
# auth.ts is imported by login.ts and sub.ts; routes.ts and login.test.ts import
# login.ts, so they sit at depth 2. ext.ts imports a package (expected not to
# resolve) and a missing relative file (a real gap).
BASE="$BT/base"
mkdir -p "$BASE"
bt_git "$BASE" init -q .
bt_git "$BASE" symbolic-ref HEAD refs/heads/main
bt_git "$BASE" config user.email t@t
bt_git "$BASE" config user.name t
bt_git "$BASE" config core.autocrlf false
bt_write "$BASE" src/lib/auth.ts <<'EOF'
export function verify(t: string) { return t === 'ok' }
export class Base {}
export const $store = 1
EOF
bt_write "$BASE" src/lib/decoy.ts <<'EOF'
export function verify() { return false }
EOF
bt_write "$BASE" src/lib/other.ts <<'EOF'
export const other = 1
EOF
bt_write "$BASE" src/lib/ext.ts <<'EOF'
import _ from 'lodash'
import { gone } from './missing'
export const ext = _.noop && gone
EOF
bt_write "$BASE" src/api/login.ts <<'EOF'
import { verify } from '../lib/auth'
export const login = (t: string) => verify(t)
EOF
bt_write "$BASE" src/api/sub.ts <<'EOF'
import { Base } from '../lib/auth'
export class Sub extends Base {}
EOF
bt_write "$BASE" src/api/routes.ts <<'EOF'
import { login } from './login'
export const routes = [login]
EOF
bt_write "$BASE" src/api/login.test.ts <<'EOF'
import { login } from './login'
login('ok')
EOF
bt_write "$BASE" go/repo.go <<'EOF'
package repo

type Repo struct{}

func (r *Repo) FindUser(id int) int { return id }
EOF
bt_write "$BASE" go/use.go <<'EOF'
package repo

func use(r *Repo) int { return r.FindUser(1) }
EOF
bt_write "$BASE" kt/Auth.kt <<'EOF'
const val DEFAULT_TTL = 5
fun parseToken(t: String) = t
EOF
bt_write "$BASE" kt/Use.kt <<'EOF'
val x = DEFAULT_TTL + parseToken("a").length
EOF
bt_write "$BASE" pkg/src/lib/a.ts <<'EOF'
export const a = 1
EOF
bt_write "$BASE" pkg/src/api/b.ts <<'EOF'
import { a } from '../lib/a'
export const b = a
EOF
printf 'gen/\n' > "$BASE/.gitignore"
bt_git "$BASE" add -A
bt_git "$BASE" commit -q -m init

bt_clone() { cp -R "$BASE" "$BT/$1"; BT_DIR="$BT/$1"; }

if [ ! -d "$BASE/.git" ] || ! ( cd "$BASE" && git rev-parse --verify -q HEAD >/dev/null 2>&1 ); then
  note "git unavailable - blast-radius scratch-repo tests skipped"
else

# --- output contract ---------------------------------------------------------------
bt_clone contract
bt_run --root "$BT_DIR" --file src/lib/auth.ts --out "$BT_DIR/.g"
BT_FIRST="$(printf '%s\n' "$BT_OUT" | sed -n 1p)"
if [ "$BT_FIRST" = "blast-radius: seeds=1 affected=4 depth=2 edges=5 gaps=1" ] && [ "$BT_RC" -eq 0 ]; then
  pass "blast-radius opens with the stats line"
else
  fail "blast-radius stats line is wrong: '$BT_FIRST' (exit $BT_RC)"
fi
if bt_in "$BT_OUT" "Depth 1" "src/api/login.ts:1 -> src/lib/auth.ts" \
   && bt_in "$BT_OUT" "Depth 1" "src/api/sub.ts:1 -> src/lib/auth.ts" \
   && bt_in "$BT_OUT" "Depth 2" "src/api/routes.ts:1 -> src/api/login.ts"; then
  pass "importers are listed by depth as path:line -> via"
else
  fail "importers are not under the right depth headers"; printf '%s\n' "$BT_OUT" | head -14 | sed 's/^/        /'
fi
if bt_in "$BT_OUT" "Tests to run" "src/api/login.test.ts"; then
  pass "Tests to run lists an affected *.test.ts"
else
  fail "Tests to run is missing src/api/login.test.ts"
fi
if ! printf '%s\n' "$BT_OUT" | grep -q '^## Name matches'; then
  pass "an empty Name matches section is not printed"
else
  fail "Name matches is printed for a file with no symbol"
fi
BT_SPOTS="$(bt_sect "$BT_OUT" "Blind spots")"
case "$BT_SPOTS" in
  *relative-path-has-no-file*) pass "Blind spots names an actionable unresolved import" ;;
  *) fail "Blind spots lacks the missing relative import: $BT_SPOTS" ;;
esac
case "$BT_SPOTS" in
  *external-package*) fail "Blind spots counts external-package, which is expected" ;;
  *) pass "Blind spots leaves out external-package" ;;
esac
case "$BT_OUT" in
  *"never as a complete one"*) pass "the incomplete-coverage footer is always printed" ;;
  *) fail "the incomplete-coverage footer is missing" ;;
esac

bt_run --root "$BT_DIR" --file src/lib/auth.ts --out "$BT_DIR/.g"; BT_A="$BT_OUT"
bt_run --root "$BT_DIR" --file src/lib/auth.ts --out "$BT_DIR/.g2"; BT_B="$BT_OUT"
bt_run --root "$BT_DIR" verify --out "$BT_DIR/.g"; BT_C="$BT_OUT"
bt_run --root "$BT_DIR" verify --out "$BT_DIR/.g2"; BT_D="$BT_OUT"
if [ "$BT_A" = "$BT_B" ] && [ "$BT_C" = "$BT_D" ] && [ -n "$BT_A" ] && [ -n "$BT_C" ]; then
  pass "two runs print identical output"
else
  fail "blast-radius output differs between two runs"
fi

# --max cuts by depth, then by path: the first rows are kept, the rest counted.
bt_run --root "$BT_DIR" --file src/lib/auth.ts --out "$BT_DIR/.g" --max 1
if bt_in "$BT_OUT" "Depth 1" "src/api/login.ts" && ! bt_in "$BT_OUT" "Depth 1" "src/api/sub.ts:" \
   && bt_in "$BT_OUT" "Depth 1" "1 more at this depth"; then
  pass "--max keeps the first path at each depth and counts the rest"
else
  fail "--max did not cut Depth 1 by path"; printf '%s\n' "$BT_OUT" | head -12 | sed 's/^/        /'
fi

# --- argument handling -----------------------------------------------------------------
bt_run --root "$BT_DIR" --bogus --diff
if [ "$BT_RC" -eq 1 ]; then pass "an unknown flag exits 1"; else fail "an unknown flag exited $BT_RC"; fi
bt_run --root "$BT_DIR" --file
if [ "$BT_RC" -eq 1 ]; then pass "--file with no value exits 1"; else fail "--file with no value exited $BT_RC"; fi
bt_run --root "$BT_DIR" --diff --base
if [ "$BT_RC" -eq 1 ]; then pass "--base with no value exits 1"; else fail "--base with no value exited $BT_RC"; fi
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" 'src\lib\auth.ts'
BT_WIN="$(printf '%s\n' "$BT_OUT" | sed -n 1p)"
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" --file 'src\lib\auth.ts'
if [ "$(printf '%s\n' "$BT_OUT" | sed -n 1p)" = "$BT_WIN" ] && bt_in "$BT_OUT" "Seeds" "src/lib/auth.ts" \
   && bt_in "$BT_OUT" "Depth 1" "src/api/login.ts"; then
  pass "a backslash path is normalised, and a bare path means --file"
else
  fail "backslash path handling is wrong"; printf '%s\n' "$BT_OUT" | head -6 | sed 's/^/        /'
fi

# --- symbol mode -----------------------------------------------------------------------
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" Base
BT_SEEDS="$(bt_seeds "$BT_OUT")"
if [ "$BT_SEEDS" = "src/lib/auth.ts" ]; then
  pass "symbol mode seeds the definer, not the file that says extends"
else
  fail "symbol mode seeded the wrong files for Base: $BT_SEEDS"
fi
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" '$store'
if [ "$(bt_seeds "$BT_OUT")" = "src/lib/auth.ts" ] && [ "$BT_RC" -eq 0 ]; then
  pass "a symbol containing \$ matches its definition"
else
  fail "a \$ symbol did not seed its definition: $(bt_seeds "$BT_OUT")"
fi
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" verify
BT_SEEDS="$(bt_seeds "$BT_OUT")"
case "$BT_SEEDS" in
  *src/lib/auth.ts*src/lib/decoy.ts*) pass "an unscoped symbol seeds every definition" ;;
  *) fail "verify should seed both definitions: $BT_SEEDS" ;;
esac
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" verify --file src/lib/auth.ts
if [ "$(bt_seeds "$BT_OUT" | sed -n 1p)" = "src/lib/auth.ts" ] \
   && ! bt_in "$BT_OUT" "Seeds" "decoy.ts" && bt_in "$BT_OUT" "Depth 1" "src/api/login.ts"; then
  pass "SYMBOL --file F scopes the definition to F"
else
  fail "SYMBOL --file F did not scope to F"; printf '%s\n' "$BT_OUT" | head -8 | sed 's/^/        /'
fi
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" verify --file src/lib/other.ts
if [ "$BT_RC" -eq 2 ]; then pass "SYMBOL --file F exits 2 when F never names the symbol"; else fail "verify --file other.ts exited $BT_RC"; fi
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" NoSuchThing
if [ "$BT_RC" -eq 2 ]; then pass "an unknown symbol exits 2"; else fail "an unknown symbol exited $BT_RC"; fi
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" FindUser
if [ "$(bt_seeds "$BT_OUT")" = "go/repo.go" ]; then pass "a Go method definition is seeded"; else fail "FindUser seeded: $(bt_seeds "$BT_OUT")"; fi
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" DEFAULT_TTL
if [ "$(bt_seeds "$BT_OUT")" = "kt/Auth.kt" ]; then pass "a Kotlin val is seeded"; else fail "DEFAULT_TTL seeded: $(bt_seeds "$BT_OUT")"; fi
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" parseToken
if [ "$(bt_seeds "$BT_OUT")" = "kt/Auth.kt" ]; then pass "a Kotlin fun is seeded"; else fail "parseToken seeded: $(bt_seeds "$BT_OUT")"; fi

# Name matches: a use with no import path to the seed is listed apart, and a
# file .gitignore hides is never searched.
bt_write "$BT_DIR" gen/built.ts <<'EOF'
export const built = verify('x')
EOF
bt_write "$BT_DIR" src/lib/note.ts <<'EOF'
// verify is described here, never imported
EOF
bt_run --root "$BT_DIR" --out "$BT_DIR/.g" verify --file src/lib/auth.ts
if bt_in "$BT_OUT" "Name matches" "src/lib/note.ts" && ! printf '%s\n' "$BT_OUT" | grep -q 'gen/built.ts'; then
  pass "name matches are listed apart, and .gitignore is honoured"
else
  fail "name matches or .gitignore handling is wrong"; printf '%s\n' "$BT_OUT" | head -14 | sed 's/^/        /'
fi
# With the default graph directory, the graph's own files are never searched or seeded.
bt_run --root "$BT_DIR" login
if ! printf '%s\n' "$BT_OUT" | grep -q 'context-graph'; then
  pass "the graph output directory is never searched"
else
  fail "the report mentions .claude/context-graph"
fi

# Outside git the search is grep -r with the vendor directories left out.
NG="$BT/nogit"
bt_write "$NG" src/a.ts <<'EOF'
export function foo() {}
EOF
bt_write "$NG" src/b.ts <<'EOF'
import { foo } from './a'
foo()
EOF
bt_write "$NG" node_modules/pkg/index.ts <<'EOF'
export const foo = 'vendored'
EOF
if ( cd "$NG" && git rev-parse --is-inside-work-tree ) >/dev/null 2>&1; then
  note "scratch directory sits inside a git work tree - non-git search untested"
else
  bt_run --root "$NG" --out "$NG/.g" foo
  if [ "$(bt_seeds "$BT_OUT")" = "src/a.ts" ] && bt_in "$BT_OUT" "Depth 1" "src/b.ts:1 -> src/a.ts"; then
    pass "outside git, symbol search skips node_modules and still finds importers"
  else
    fail "non-git symbol search is wrong"; printf '%s\n' "$BT_OUT" | head -8 | sed 's/^/        /'
  fi
fi

# --- --diff ------------------------------------------------------------------------------
bt_clone cleandiff
bt_run --root "$BT_DIR" --diff
if [ "$BT_RC" -eq 0 ] && printf '%s\n' "$BT_OUT" | grep -q 'nothing changed'; then
  pass "--diff on a clean tree exits 0 and says nothing changed"
else
  fail "clean --diff: exit $BT_RC: $BT_OUT"
fi

bt_clone delunstaged
rm -f "$BT_DIR/src/lib/auth.ts"
bt_run --root "$BT_DIR" --diff
if bt_in "$BT_OUT" "Seeds" "src/lib/auth.ts   [deleted]" && bt_in "$BT_OUT" "Depth 1" "src/api/login.ts" \
   && bt_in "$BT_OUT" "Depth 1" "src/api/sub.ts"; then
  pass "--diff keeps an unstaged deletion as a seed and lists its importers"
else
  fail "--diff lost the importers of an unstaged deletion"; printf '%s\n' "$BT_OUT" | head -10 | sed 's/^/        /'
fi

bt_clone delstaged
bt_git "$BT_DIR" rm -q src/lib/auth.ts
bt_run --root "$BT_DIR" --diff
if bt_in "$BT_OUT" "Seeds" "src/lib/auth.ts   [deleted]" && bt_in "$BT_OUT" "Depth 1" "src/api/login.ts"; then
  pass "--diff lists the importers of a staged deletion"
else
  fail "--diff lost the importers of a staged deletion"; printf '%s\n' "$BT_OUT" | head -10 | sed 's/^/        /'
fi

bt_clone delcommitted
bt_git "$BT_DIR" checkout -q -b feat
bt_git "$BT_DIR" rm -q src/lib/auth.ts
bt_git "$BT_DIR" commit -q -m "drop auth"
bt_run --root "$BT_DIR" --diff --base main
if bt_in "$BT_OUT" "Seeds" "src/lib/auth.ts   [deleted]" && bt_in "$BT_OUT" "Depth 1" "src/api/login.ts"; then
  pass "--diff --base lists the importers of a file deleted on the branch"
else
  fail "--diff --base lost the importers of a committed deletion"; printf '%s\n' "$BT_OUT" | head -10 | sed 's/^/        /'
fi

bt_clone renamed
bt_git "$BT_DIR" mv src/lib/auth.ts src/lib/authn.ts
bt_run --root "$BT_DIR" --diff
if bt_in "$BT_OUT" "Seeds" "src/lib/auth.ts   [renamed to src/lib/authn.ts]" \
   && bt_in "$BT_OUT" "Seeds" "src/lib/authn.ts   [renamed from src/lib/auth.ts]" \
   && bt_in "$BT_OUT" "Depth 1" "src/api/login.ts:1 -> src/lib/auth.ts"; then
  pass "--diff seeds both sides of a rename and finds the old path's importers"
else
  fail "--diff did not use the old path of a rename"; printf '%s\n' "$BT_OUT" | head -12 | sed 's/^/        /'
fi

bt_clone subroot
printf 'export const a = 2\n' > "$BT_DIR/pkg/src/lib/a.ts"
printf 'export const other = 2\n' > "$BT_DIR/src/lib/other.ts"
bt_run --root "$BT_DIR/pkg" --diff
if [ "$(bt_seeds "$BT_OUT")" = "src/lib/a.ts" ] && bt_in "$BT_OUT" "Depth 1" "src/api/b.ts:1 -> src/lib/a.ts"; then
  pass "--diff works when the project root is below the git top level"
else
  fail "--diff from a subdirectory root is wrong"; printf '%s\n' "$BT_OUT" | head -10 | sed 's/^/        /'
fi

bt_clone basedirty
bt_git "$BT_DIR" checkout -q -b feat
printf 'export const other = 3\n' > "$BT_DIR/src/lib/other.ts"
bt_git "$BT_DIR" commit -q -am "other"
printf 'export class Base {}\nexport const edited = 1\n' > "$BT_DIR/src/lib/auth.ts"
printf 'export const fresh = 1\n' > "$BT_DIR/src/lib/fresh.ts"
bt_run --root "$BT_DIR" --diff --base main
BT_SEEDS="$(bt_seeds "$BT_OUT")"
case "$BT_SEEDS" in
  *src/lib/auth.ts*src/lib/fresh.ts*src/lib/other.ts*)
    if [ "$(printf '%s\n' "$BT_OUT" | sed -n 1p | cut -d' ' -f2)" = "seeds=3" ]; then
      pass "--diff --base counts committed, uncommitted and untracked work"
    else
      fail "--diff --base seed count is wrong: $(printf '%s\n' "$BT_OUT" | sed -n 1p)"
    fi ;;
  *) fail "--diff --base missed a change: $BT_SEEDS" ;;
esac
# A second run must not turn the graph it wrote into seeds.
bt_run --root "$BT_DIR" --diff --base main
if [ "$(bt_seeds "$BT_OUT")" = "$BT_SEEDS" ]; then pass "the graph directory never becomes a seed"; else fail "second --diff changed the seeds"; fi

bt_clone badbase
bt_run --root "$BT_DIR" --diff --base no-such-ref
if [ "$BT_RC" -eq 1 ] && printf '%s\n' "$BT_OUT" | grep -q 'unknown base ref'; then
  pass "an invalid --base exits 1 with a clear error"
else
  fail "invalid --base: exit $BT_RC: $BT_OUT"
fi

# An untracked seed with a committed importer: the importer's import only
# resolves once the new file exists.
bt_clone untracked
bt_write "$BT_DIR" src/api/early.ts <<'EOF'
import { late } from './late'
export const early = late
EOF
bt_git "$BT_DIR" add -A
bt_git "$BT_DIR" commit -q -m "early"
bt_write "$BT_DIR" src/api/late.ts <<'EOF'
export const late = 1
EOF
bt_run --root "$BT_DIR" --diff
if [ "$(bt_seeds "$BT_OUT")" = "src/api/late.ts" ] && bt_in "$BT_OUT" "Depth 1" "src/api/early.ts:1 -> src/api/late.ts"; then
  pass "--diff finds the committed importer of an untracked file"
else
  fail "--diff missed the importer of an untracked file"; printf '%s\n' "$BT_OUT" | head -8 | sed 's/^/        /'
fi

fi # git available

# --- the CLAUDE.md section ----------------------------------------------------------------
BT_SEC="templates/sections/60-blast-radius.md"
if [ -f "$BT_SEC" ]; then
  BT_LINES="$(wc -l < "$BT_SEC" | tr -d ' ')"
  if [ "$BT_LINES" -le 10 ]; then pass "the blast-radius section is $BT_LINES lines (10 or fewer)"; else fail "the blast-radius section is $BT_LINES lines"; fi
  mkdir -p "$BT/sec/data"
  printf '# T\n' > "$BT/sec/CLAUDE.md"
  BT_ST="$(CONTEXT_KIT_LEVEL= CLAUDE_PLUGIN_DATA="$BT/sec/data" sh scripts/claude-sections.sh stamp "$BT/sec/CLAUDE.md" 2>&1)"
  BT_STATUS="$(CONTEXT_KIT_LEVEL= CLAUDE_PLUGIN_DATA="$BT/sec/data" sh scripts/claude-sections.sh status "$BT/sec/CLAUDE.md" 2>&1)"
  if grep -qF '<!-- context-kit:begin blast-radius -->' "$BT/sec/CLAUDE.md" \
     && grep -qF '<!-- context-kit:end blast-radius -->' "$BT/sec/CLAUDE.md" \
     && grep -q 'blast-radius' "$BT/sec/CLAUDE.md" \
     && printf '%s\n' "$BT_STATUS" | grep -q '^ok blast-radius'; then
    pass "claude-sections.sh stamps the blast-radius section and reports it ok"
  else
    fail "the blast-radius section did not stamp cleanly: $BT_ST / $BT_STATUS"
  fi
else
  fail "templates/sections/60-blast-radius.md is missing"
fi

if [ "$BT_STANDALONE" -eq 1 ]; then
  if [ "$FAIL" -eq 0 ]; then printf '\nAll blast-radius checks passed.\n'; else printf '\nblast-radius checks failed.\n'; fi
  exit "$FAIL"
fi
