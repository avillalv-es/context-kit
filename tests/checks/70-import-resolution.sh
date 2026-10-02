# Import resolution for this org's stack: Vue 3 + TypeScript (create-vue, Vite)
# and .NET 9 (C#). Sourced by scripts/check.sh, which supplies pass/fail/note
# and $TMP. Runnable alone too:  sh tests/checks/70-import-resolution.sh
#
# Two kinds of test. The vue and dotnet fixtures under tests/fixtures/imports/
# have their whole edge sets asserted by check.sh section 16 (here, only when
# run alone), and the first half of this file pins the CLAIMS those edge sets
# exist to prove. The second half builds scratch repos for the cases a fixture
# would only clutter: alias inheritance, JSONC, the C# edge cases, the fan-out
# cap. Every name below carries an ir_ / IR_ prefix: this file is sourced into
# the shell check.sh runs in, and must not trample its variables.

IR_STANDALONE=0
if ! command -v pass >/dev/null 2>&1; then
  IR_STANDALONE=1
  FAIL=0
  note() { printf '  %s\n' "$1"; }
  fail() { printf 'FAIL  %s\n' "$1"; FAIL=1; }
  pass() { printf 'ok    %s\n' "$1"; }
  cd "$(dirname "$0")/../.." || exit 1
  TMP="$(mktemp -d)" || exit 1
fi

IR_W="$TMP/ir"
mkdir -p "$IR_W"

# --- helpers ----------------------------------------------------------------
ir_graph() { sh scripts/code-graph.sh --root "$1" --out "$2" --quiet >/dev/null 2>&1; }
ir_put()   { mkdir -p "$(dirname "$1")" && cat > "$1"; }

# ir_edge IMPORTS FROM TO [FORM [CONFIDENCE]]  succeeds when that edge exists
ir_edge() {
  awk -F'\t' -v f="$2" -v t="$3" -v fm="${4:-}" -v cf="${5:-}" '
    $1 == f && $2 == t && (fm == "" || $4 == fm) && (cf == "" || $5 == cf) { found = 1 }
    END { exit !found }' "$1"
}
# ir_from IMPORTS FROM / ir_into IMPORTS TO  print how many edges leave / arrive
ir_from() { awk -F'\t' -v f="$2" '$1 == f { n++ } END { print n + 0 }' "$1"; }
ir_into() { awk -F'\t' -v t="$2" '$2 == t { n++ } END { print n + 0 }' "$1"; }
# ir_reason UNRESOLVED FROM MODULE REASON  succeeds when that drop was logged
ir_reason() {
  awk -F'\t' -v f="$2" -v m="$3" -v r="$4" '$1 == f && $2 == m && $3 == r { found = 1 } END { exit !found }' "$1"
}
# ir_rows UNRESOLVED FROM  prints how many drops were logged for FROM
ir_rows() { awk -F'\t' -v f="$2" '$1 == f { n++ } END { print n + 0 }' "$1"; }

ir_yes() { IR_D="$1"; shift; if "$@"; then pass "$IR_D"; else fail "$IR_D"; fi; }
ir_no()  { IR_D="$1"; shift; if "$@"; then fail "$IR_D"; else pass "$IR_D"; fi; }
ir_eq()  { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got $2, want $3)"; fi; }

# --- the dotnet fixture: namespaces, not file names -------------------------
ir_graph tests/fixtures/imports/dotnet "$IR_W/dotnet"
IR_DI="$IR_W/dotnet/imports.tsv"
IR_DU="$IR_W/dotnet/unresolved.tsv"
IR_API=src/Contoso.Metering.Api
IR_COR=src/Contoso.Metering.Core
IR_ABS=src/Contoso.Metering.Abstractions
IR_STO=src/Contoso.Metering.Storage
IR_TEL=src/Contoso.Metering.Telemetry

ir_no  "C# no longer suffix-matches a namespace to a file name (the Telemetry.cs edge is gone)" \
       ir_edge "$IR_DI" "$IR_API/TelemetryStartup.cs" "$IR_STO/Telemetry.cs"
ir_yes "C# 'using Telemetry;' lands on the file that declares namespace Telemetry" \
       ir_edge "$IR_DI" "$IR_API/TelemetryStartup.cs" "$IR_TEL/Counters.cs" using-namespace INFERRED
ir_yes "C# a file-scoped declaration of a namespace is reached" \
       ir_edge "$IR_DI" "$IR_API/ReadingsController.cs" "$IR_ABS/IMeterReader.cs" using-namespace INFERRED
ir_yes "C# a block-scoped declaration of the same namespace is reached too" \
       ir_edge "$IR_DI" "$IR_API/ReadingsController.cs" "$IR_ABS/Units.cs" using-namespace INFERRED
ir_yes "C# 'global using' of a declared namespace resolves, from the file that carries it" \
       ir_edge "$IR_DI" "$IR_COR/GlobalUsings.cs" "$IR_ABS/IMeterReader.cs" using-namespace INFERRED
ir_eq  "C# a global using of System.* draws no edge (GlobalUsings.cs reaches only Abstractions)" \
       "$(ir_from "$IR_DI" "$IR_COR/GlobalUsings.cs")" 2
ir_yes "C# 'using static Telemetry.Counters;' resolves through the namespace one segment up" \
       ir_edge "$IR_DI" "$IR_STO/MeterSink.cs" "$IR_TEL/Counters.cs" using-namespace INFERRED
ir_yes "C# an alias to a type resolves through its namespace" \
       ir_edge "$IR_DI" "$IR_STO/MeterSink.cs" "$IR_TEL/Options.cs" using-namespace INFERRED
ir_yes "C# a using wrapped across lines resolves" \
       ir_edge "$IR_DI" "$IR_STO/MultiLineUsings.cs" "$IR_ABS/IMeterReader.cs" using-namespace
ir_yes "C# an external namespace is logged as unresolved (Serilog)" \
       ir_reason "$IR_DU" "$IR_COR/ReadingParser.cs" Serilog external-or-stdlib
ir_eq  "C# an external namespace draws no edge (ReadingParser.cs reaches only Abstractions)" \
       "$(ir_from "$IR_DI" "$IR_COR/ReadingParser.cs")" 2
ir_yes "C# a namespace declared nowhere drops even though two files share its name (Options)" \
       ir_reason "$IR_DU" "$IR_API/TelemetryStartup.cs" Options external-or-stdlib
ir_eq  "C# usings in a comment or a string draw no edge into files that declare those namespaces" \
       "$(ir_into "$IR_DI" "$IR_COR/Decoys.cs")" 0
ir_eq  "C# namespaces declared only in a comment or a verbatim string draw no edge (Bootstrap.cs)" \
       "$(ir_from "$IR_DI" "$IR_API/Bootstrap.cs")" 0
ir_eq  "C# using statements (var, parenthesised) are not logged as unresolved imports" \
       "$(awk -F'\t' '$1 ~ /ReadingParser\.cs$/ && $2 ~ /[(=]/ { n++ } END { print n + 0 }' "$IR_DU")" 0
ir_yes ".csproj ProjectReference edges are kept" \
       ir_edge "$IR_DI" "$IR_API/Contoso.Metering.Api.csproj" "$IR_COR/Contoso.Metering.Core.csproj" project-reference EXTRACTED

# --- the vue fixture: create-vue + Vite -------------------------------------
IR_VF=tests/fixtures/imports/vue
ir_graph "$IR_VF" "$IR_W/vue"
IR_VI="$IR_W/vue/imports.tsv"
if grep -q '"paths"' "$IR_VF/tsconfig.json" 2>/dev/null; then
  fail "vue fixture is not create-vue shaped: tsconfig.json should hold no paths"
else
  pass "vue fixture: tsconfig.json holds only references, as create-vue generates it"
fi
ir_yes "vue '@/' resolves through tsconfig.app.json, from a .vue <script setup lang=\"ts\">" \
       ir_edge "$IR_VI" src/App.vue src/components/UserCard.vue import INFERRED
ir_yes "vue '@/' resolves for a side-effect import of a stylesheet" \
       ir_edge "$IR_VI" src/main.ts src/assets/main.css import-side-effect INFERRED
ir_yes "vue a barrel is reached through the alias" \
       ir_edge "$IR_VI" src/App.vue src/components/index.ts import INFERRED
ir_yes "vue the barrel's re-exports resolve" \
       ir_edge "$IR_VI" src/components/index.ts src/components/UserCard.vue import EXTRACTED
if grep -q '~' "$IR_VF"/tsconfig*.json 2>/dev/null; then
  fail "vue fixture: a tsconfig declares the '~' aliases, so they no longer prove the vite config is read"
else
  pass "vue fixture: no tsconfig declares the '~' aliases"
fi
ir_yes "vue a vite-only alias resolves (path.resolve form, '~lib')" \
       ir_edge "$IR_VI" src/components/StatusBadge.vue src/lib/format.ts import INFERRED
ir_yes "vue a vite-only alias resolves (root-relative '/src' form, '~/')" \
       ir_edge "$IR_VI" src/stores/user.ts src/types/user.ts import INFERRED
ir_eq  "vue a comment and two strings holding an import draw no edge (Ghost.vue)" \
       "$(ir_into "$IR_VI" src/components/Ghost.vue)" 0
ir_eq  "vue aliases that are not literals, or sit in a comment, are skipped (skipped.ts)" \
       "$(ir_from "$IR_VI" src/skipped.ts)" 0

# --- tsconfig: inheritance, JSONC, scope ------------------------------------
IR_TS="$IR_W/ts-src"
# (a) comments are not config, and "@/*" is a key, not the start of a comment
ir_put "$IR_TS/app/tsconfig.json" <<'EOF'
{
  // "paths": { "@x/*": ["x/*"] }
  "compilerOptions": {
    /* "paths": { "@y/*": ["y/*"] } */
    "paths": { "@/*": ["./src/*"] }
  }
}
EOF
ir_put "$IR_TS/app/src/a.ts" <<'EOF'
import { b } from '@/b'
import { f } from '@x/f'
import { g } from '@y/f'
EOF
printf 'export const b = 1\n' | ir_put "$IR_TS/app/src/b.ts"
printf 'export const f = 1\n' | ir_put "$IR_TS/app/x/f.ts"
printf 'export const g = 1\n' | ir_put "$IR_TS/app/y/f.ts"
# (b) a base config in another directory, under a name no glob would find:
#     its baseUrl and its paths are inherited by the config that extends it
ir_put "$IR_TS/config/base.json" <<'EOF'
{ "compilerOptions": { "baseUrl": "../lib1/src", "paths": { "@lib/*": ["*"], "~core": ["core/index.ts"] } } }
EOF
ir_put "$IR_TS/lib1/tsconfig.json" <<'EOF'
{ "extends": "../config/base.json" }
EOF
ir_put "$IR_TS/lib1/src/m.ts" <<'EOF'
import { u } from '@lib/util'
import { c } from '~core'
EOF
printf 'export const u = 1\n' | ir_put "$IR_TS/lib1/src/util.ts"
printf 'export const c = 1\n' | ir_put "$IR_TS/lib1/src/core/index.ts"
# (c) the extending config's paths REPLACE the base's, baseUrl still comes
#     from the base, and the alias applies below the config's directory only
ir_put "$IR_TS/config/base2.json" <<'EOF'
{ "compilerOptions": { "baseUrl": "../web/src", "paths": { "@old/*": ["old/*"] } } }
EOF
ir_put "$IR_TS/web/tsconfig.json" <<'EOF'
{ "extends": "../config/base2.json", "compilerOptions": { "paths": { "~/*": ["lib/*"] } } }
EOF
ir_put "$IR_TS/web/src/page.ts" <<'EOF'
import { x } from '~/x'
import { z } from '@old/z'
EOF
printf 'export const x = 1\n' | ir_put "$IR_TS/web/src/lib/x.ts"
printf 'export const z = 1\n' | ir_put "$IR_TS/web/src/old/z.ts"
printf "import { x } from '~/x'\n" | ir_put "$IR_TS/other/o.ts"
# (d) a tsconfig.*.json no fixed list would name, with the TypeScript 5 array
#     form of extends, where a later config's paths replace an earlier one's
ir_put "$IR_TS/multi/tsconfig.build.json" <<'EOF'
{ "extends": ["./one.json", "./two.json"] }
EOF
ir_put "$IR_TS/multi/one.json" <<'EOF'
{ "compilerOptions": { "paths": { "@one/*": ["a/*"] } } }
EOF
ir_put "$IR_TS/multi/two.json" <<'EOF'
{ "compilerOptions": { "paths": { "@two/*": ["b/*"] } } }
EOF
ir_put "$IR_TS/multi/s.ts" <<'EOF'
import { a } from '@one/a'
import { b } from '@two/b'
EOF
printf 'export const a = 1\n' | ir_put "$IR_TS/multi/a/a.ts"
printf 'export const b = 1\n' | ir_put "$IR_TS/multi/b/b.ts"
ir_graph "$IR_TS" "$IR_W/ts-out"
IR_TI="$IR_W/ts-out/imports.tsv"
ir_yes "tsconfig a '@/*' key is not mistaken for a block comment" \
       ir_edge "$IR_TI" app/src/a.ts app/src/b.ts import INFERRED
ir_eq  "tsconfig a paths block inside a // or /* */ comment is not read" \
       "$(ir_from "$IR_TI" app/src/a.ts)" 1
ir_yes "tsconfig extends: paths and baseUrl are inherited from a base in another directory" \
       ir_edge "$IR_TI" lib1/src/m.ts lib1/src/util.ts import INFERRED
ir_yes "tsconfig extends: an inherited exact alias resolves" \
       ir_edge "$IR_TI" lib1/src/m.ts lib1/src/core/index.ts import INFERRED
ir_yes "tsconfig extends: baseUrl comes from the base when the config only declares paths" \
       ir_edge "$IR_TI" web/src/page.ts web/src/lib/x.ts import INFERRED
ir_no  "tsconfig extends: the child's paths replace the base's, they are not merged" \
       ir_edge "$IR_TI" web/src/page.ts web/src/old/z.ts
ir_no  "tsconfig an alias does not reach files outside the config's own directory" \
       ir_edge "$IR_TI" other/o.ts web/src/lib/x.ts
ir_yes "tsconfig the extends array: the last config's alias resolves" \
       ir_edge "$IR_TI" multi/s.ts multi/b/b.ts import INFERRED
ir_no  "tsconfig the extends array: an earlier config's replaced alias does not" \
       ir_edge "$IR_TI" multi/s.ts multi/a/a.ts

# --- vite.config: literal aliases, in the forms it can be read --------------
IR_VT="$IR_W/vite-src"
ir_put "$IR_VT/vite.config.mjs" <<'EOF'
import { defineConfig } from 'vite'
import path from 'node:path'

const origin = 'http://localhost:5173' // a // inside a string is not a comment
const dyn = 'x'

export default defineConfig(({ mode }) => ({
  resolve: {
    alias: [
      { find: '@components', replacement: path.resolve(__dirname, 'src/components') },
      { find: '#shared', replacement: path.join(__dirname, 'src', 'shared') },
      { find: /^@re\//, replacement: '/src/re/' },
      { find: '@dyn', replacement: `/src/${dyn}` },
    ],
  },
}))
EOF
ir_put "$IR_VT/src/app.ts" <<'EOF'
import { Btn } from '@components/Btn'
import { s } from '#shared/s'
import { r } from '@re/q'
import { d } from '@dyn/z'
EOF
printf 'export const Btn = 1\n' | ir_put "$IR_VT/src/components/Btn.ts"
printf 'export const s = 1\n' | ir_put "$IR_VT/src/shared/s.ts"
printf 'export const r = 1\n' | ir_put "$IR_VT/src/re/q.ts"
printf 'export const d = 1\n' | ir_put "$IR_VT/src/x/z.ts"
ir_put "$IR_VT/web2/vite.config.ts" <<'EOF'
import path from 'path'
export default { resolve: { alias: { '@': path.resolve(__dirname, './src') } } }
EOF
printf "import { q } from '@/q'\n" | ir_put "$IR_VT/web2/src/p.ts"
printf 'export const q = 1\n' | ir_put "$IR_VT/web2/src/q.ts"
printf "import { q } from '@/q'\n" | ir_put "$IR_VT/rootfile.ts"
ir_graph "$IR_VT" "$IR_W/vite-out"
IR_XI="$IR_W/vite-out/imports.tsv"
ir_yes "vite alias array: { find, replacement: path.resolve(...) } resolves" \
       ir_edge "$IR_XI" src/app.ts src/components/Btn.ts import INFERRED
ir_yes "vite alias: path.join(__dirname, 'src', 'shared') resolves" \
       ir_edge "$IR_XI" src/app.ts src/shared/s.ts import INFERRED
ir_eq  "vite alias: a regex find and a template-literal replacement are skipped, not guessed" \
       "$(ir_from "$IR_XI" src/app.ts)" 2
ir_yes "vite alias object in a nested package resolves ('./src' is relative to that config)" \
       ir_edge "$IR_XI" web2/src/p.ts web2/src/q.ts import INFERRED
ir_no  "vite alias applies only below the directory of its config" \
       ir_edge "$IR_XI" rootfile.ts web2/src/q.ts

# --- C#: exact namespaces, using statements, nesting, the fan-out cap -------
IR_CS="$IR_W/cs-src"
ir_put "$IR_CS/Deep.cs" <<'EOF'
namespace Acme.Core.Deep;
public static class Helper { }
EOF
ir_put "$IR_CS/Top.cs" <<'EOF'
namespace Acme.Core;
public class Top { }
EOF
ir_put "$IR_CS/OnlyCore.cs" <<'EOF'
using Acme.Core;
public class OnlyCore { }
EOF
ir_put "$IR_CS/Static.cs" <<'EOF'
using static Acme.Core.Deep.Helper;
using static Acme.Core.Deep.Helper.Nested.Inner.Far;
public class Static { }
EOF
ir_put "$IR_CS/Stmts.cs" <<'EOF'
using System;

namespace Acme.Stmts;

public class Stmts
{
    void F()
    {
        using var a = Make();
        using (var b = Make()) { }
        using var c =
            Make();
        using System.IO.Stream d = Make();
    }
}
EOF
# Allman braces, a nested block namespace, and a brace inside a string: if that
# "}" were counted, Outer.A would close early and Outer.B would be declared as
# a bare 'B'.
ir_put "$IR_CS/Nested.cs" <<'EOF'
namespace Outer
{
    namespace A
    {
        public class X { public string S = "}"; }
    }
    namespace B
    {
        public class Y { }
    }
}
EOF
ir_put "$IR_CS/UsesNested.cs" <<'EOF'
using Outer.A;
using Outer.B;
using B;
public class UsesNested { }
EOF
ir_graph "$IR_CS" "$IR_W/cs-out"
IR_CI="$IR_W/cs-out/imports.tsv"
IR_CU="$IR_W/cs-out/unresolved.tsv"
ir_yes "C# a plain using reaches the files declaring exactly that namespace" \
       ir_edge "$IR_CI" OnlyCore.cs Top.cs using-namespace INFERRED
ir_no  "C# a plain using never reaches a child namespace (Acme.Core is not Acme.Core.Deep)" \
       ir_edge "$IR_CI" OnlyCore.cs Deep.cs
ir_yes "C# 'using static' of a type finds the namespace one segment up" \
       ir_edge "$IR_CI" Static.cs Deep.cs using-namespace INFERRED
ir_yes "C# 'using static' climbs no further than two segments, then drops as external" \
       ir_reason "$IR_CU" Static.cs Acme.Core.Deep.Helper.Nested.Inner.Far external-or-stdlib
ir_eq  "C# using statements (var, parenthesised, wrapped, typed) are never imports" \
       "$(ir_from "$IR_CI" Stmts.cs)" 0
ir_eq  "C# using statements leave no unresolved rows (only 'using System;' is logged)" \
       "$(ir_rows "$IR_CU" Stmts.cs)" 1
ir_yes "C# nested block namespaces resolve, with Allman braces" \
       ir_edge "$IR_CI" UsesNested.cs Nested.cs using-namespace INFERRED
ir_eq  "C# a brace inside a string does not close a namespace early (one drop, not two)" \
       "$(ir_rows "$IR_CU" UsesNested.cs)" 1
ir_yes "C# a nested namespace is qualified by its parent, so the bare name drops (using B)" \
       ir_reason "$IR_CU" UsesNested.cs B external-or-stdlib

# The cap: 50 files behind one using is fine, 51 is one too many. Names are
# zero-padded so path order and number order agree.
for IR_N in 50 51; do
  IR_FO="$IR_W/fan$IR_N"
  mkdir -p "$IR_FO/Models"
  IR_I=0
  while [ "$IR_I" -lt "$IR_N" ]; do
    IR_I=$((IR_I + 1))
    IR_P="$IR_I"
    [ "$IR_I" -lt 10 ] && IR_P="0$IR_I"
    printf 'namespace Big.Models;\npublic class M%s { }\n' "$IR_I" > "$IR_FO/Models/M$IR_P.cs"
  done
  printf 'using Big.Models;\nnamespace App;\npublic class Consumer { }\n' > "$IR_FO/Consumer.cs"
  ir_graph "$IR_FO" "$IR_W/fan$IR_N-out"
done
ir_eq  "C# fan-out: a namespace behind exactly 50 files gets all 50 edges" \
       "$(ir_from "$IR_W/fan50-out/imports.tsv" Consumer.cs)" 50
ir_no  "C# fan-out: and no cap reason is written at 50" \
       ir_reason "$IR_W/fan50-out/unresolved.tsv" Consumer.cs Big.Models using-namespace-fanout-capped
ir_eq  "C# fan-out: a namespace behind 51 files is capped at 50 edges" \
       "$(ir_from "$IR_W/fan51-out/imports.tsv" Consumer.cs)" 50
ir_yes "C# fan-out: the cap is written to unresolved.tsv with its own reason" \
       ir_reason "$IR_W/fan51-out/unresolved.tsv" Consumer.cs Big.Models using-namespace-fanout-capped
ir_yes "C# fan-out: the edges kept are the first 50 in path order" \
       ir_edge "$IR_W/fan51-out/imports.tsv" Consumer.cs Models/M50.cs using-namespace
ir_no  "C# fan-out: the file past the cap is the one left out" \
       ir_edge "$IR_W/fan51-out/imports.tsv" Consumer.cs Models/M51.cs

# --- run alone: the exact-set check that check.sh section 16 does -----------
if [ "$IR_STANDALONE" -eq 1 ]; then
  for IR_FAM in vue dotnet; do
    cut -f1,2 "$IR_W/$IR_FAM/imports.tsv" | sort -u > "$IR_W/got-$IR_FAM.tsv"
    grep -v '^#' "tests/fixtures/imports/$IR_FAM/EXPECTED.tsv" | grep -v '^[[:space:]]*$' | sort -u > "$IR_W/exp-$IR_FAM.tsv"
    IR_MISS="$(comm -23 "$IR_W/exp-$IR_FAM.tsv" "$IR_W/got-$IR_FAM.tsv")"
    IR_XTRA="$(comm -13 "$IR_W/exp-$IR_FAM.tsv" "$IR_W/got-$IR_FAM.tsv")"
    if [ -n "$IR_MISS" ] || [ -n "$IR_XTRA" ]; then
      fail "$IR_FAM fixture: edge set differs from EXPECTED.tsv"
      [ -n "$IR_MISS" ] && printf '%s\n' "$IR_MISS" | head -5 | sed 's/^/        missing: /'
      [ -n "$IR_XTRA" ] && printf '%s\n' "$IR_XTRA" | head -5 | sed 's/^/        extra:   /'
    else
      pass "$IR_FAM fixture: every expected edge, and no invented ones"
    fi
    if awk -F'\t' '$2 ~ /^\// || $2 ~ /\.\./ { found = 1 } END { exit !found }' "$IR_W/$IR_FAM/imports.tsv"; then
      fail "$IR_FAM fixture: an edge escaped the fixture tree"
    else
      pass "$IR_FAM fixture: no edge resolves outside the tree it came from"
    fi
  done
  rm -rf "$TMP" 2>/dev/null
  printf '\n'
  if [ "$FAIL" -eq 0 ]; then printf 'Import resolution checks passed.\n'; else printf 'Import resolution checks failed.\n'; fi
  exit "$FAIL"
fi
