# File-level import graph. POSIX awk.
#
# stdin:          source file paths, one per line, repo-relative
# -v filelist=    every file in the repo, one per line, repo-relative
# -v root=        project root (absolute)
# -v gomod=       the module path from go.mod, if any
# -v aliases=     optional "prefix<TAB>target" lines from tsconfig/jsconfig paths
# -v unresolved=  optional path to write dropped imports to
# -v bindings=    optional path to write import-binding rows to (JS/TS and
#                 Python only): from,line,to,local,imported,kind,conf,flags,
#                 module - which NAME a statement binds and to which resolved
#                 file, a subset of the edges below, never a second resolver
# -v maxfan=      cap on edges from one import statement (default 40)
#
# stdout: from<TAB>to<TAB>lang<TAB>form<TAB>confidence<TAB>line
#
# FILE level, not symbol level. It answers "which file depends on which file",
# never "which function calls which function". That is the whole trade: an
# import line changes far less often than a function body, so this stays true
# for longer than a symbol index does, and it needs no AST, no grammar per
# language, and no resolver that has to understand dynamic dispatch.
#
# It drops what it cannot justify. An import that does not resolve to a real
# file is written to the unresolved list with a reason, never guessed into an
# edge. A wrong edge in a blast-radius report is worse than a missing one:
# a missing edge makes you look further, a wrong one makes you stop looking.

# --- the index ---------------------------------------------------------------
# suffixkey lets "com/foo/Bar.java" and "util/log.h" find their file without
# scanning every path. Only a UNIQUE suffix match is ever accepted; an
# ambiguous one is dropped, because picking one of two same-named files is
# exactly how a graph starts lying.
function index_file(p,   segs, n, i, key, j) {
  exact[p] = 1
  ne = stripext(p)
  noext_n[ne]++; noext_p[ne] = p
  d = dirname(p)
  dirn[d]++; dirf[d, dirn[d]] = p
  n = split(p, segs, "/")
  key = ""
  for (i = n; i >= 1 && i > n - 5; i--) {
    key = segs[i] (key == "" ? "" : "/" key)
    suf_n[key]++; suf_p[key] = p
    kne = stripext(key)
    if (kne != key) { sufne_n[kne]++; sufne_p[kne] = p }
  }
}

# --- resolution --------------------------------------------------------------
function accept(cand) { return (cand != "" && (cand in exact)) }

# Try a base path with each candidate extension, then as a directory with an
# index / __init__ / mod entry point.
# TypeScript ESM imports carry the extension of the file that will be EMITTED
# (`./useData.js`), not the one on disk (`useData.ts`). Without this every
# import in a NodeNext codebase drops as unresolved.
function try_path_js(base,   hit, b) {
  hit = try_path(base, "js")
  if (hit != "") return hit
  if (base ~ /\.(js|jsx|mjs|cjs)$/) {
    b = base
    sub(/\.(js|jsx|mjs|cjs)$/, "", b)
    return try_path(b, "js")
  }
  return ""
}

function try_path(base, lang,   n, E, i, c) {
  if (base == "") return ""
  if (accept(base)) return base
  n = split(exts_for(lang), E, " ")
  for (i = 1; i <= n; i++) if (accept(base E[i])) return base E[i]
  if (lang == "js") {
    for (i = 1; i <= n; i++) if (accept(base "/index" E[i])) return base "/index" E[i]
  } else if (lang == "py") {
    if (accept(base "/__init__.py")) return base "/__init__.py"
  } else if (lang == "rs") {
    if (accept(base "/mod.rs")) return base "/mod.rs"
  }
  return ""
}

# A unique suffix match only. Ambiguity is a drop, not a coin flip.
function try_suffix(key, lang,   n, E, i) {
  if (key == "") return ""
  if (suf_n[key] == 1) return suf_p[key]
  if (suf_n[key] > 1) { ambiguous = 1; return "" }
  n = split(exts_for(lang), E, " ")
  for (i = 1; i <= n; i++) {
    if (suf_n[key E[i]] == 1) return suf_p[key E[i]]
    if (suf_n[key E[i]] > 1) { ambiguous = 1; return "" }
  }
  if (sufne_n[key] == 1) return sufne_p[key]
  if (sufne_n[key] > 1) ambiguous = 1
  return ""
}

function emit(from, to, lang, form, conf, lno) {
  if (to == "" || to == from) return
  k = from SUBSEP to SUBSEP form
  if (k in emitted) return
  emitted[k] = 1
  printf "%s\t%s\t%s\t%s\t%s\t%s\n", from, to, lang, form, conf, lno
  nedges++
}

function drop(from, mod, reason, lno) {
  ndropped++
  if (unresolved != "")
    printf "%s\t%s\t%s\t%s\n", from, mod, reason, lno >> unresolved
}

# --- per-language resolution -------------------------------------------------
function resolve(from, lang, mod, form, lno,   d, i, n, P, base, hit, up, rest, seg, nseg, key, croot, conf) {
  ambiguous = 0
  bindto = ""; bindconf = ""; bindalias = 0
  d = dirname(from)

  if (lang == "js") {
    if (mod ~ /^\.\.?\//) {
      base = norm(d "/" mod)
      if (base == "") { drop(from, mod, "climbs-above-root", lno); return }
      hit = try_path_js(base)
      if (hit != "") { setbind(from, hit, "EXTRACTED", 0); emit(from, hit, lang, form, "EXTRACTED", lno); return }
      drop(from, mod, "relative-path-has-no-file", lno); return
    }
    if (mod ~ /^\//) {
      hit = try_path_js(norm(mod))
      if (hit != "") { setbind(from, hit, "EXTRACTED", 0); emit(from, hit, lang, form, "EXTRACTED", lno); return }
    }
    # The nearest self-contained config shadows the outer ones. A package
    # tsconfig that declares paths and extends nothing does not inherit the
    # root's aliases, and resolving through them invents an edge for a
    # specifier that does not compile.
    shadow = ""
    for (sc in ownscope) {
      if (sc == "") continue
      if (index(from, sc "/") != 1) continue
      if (length(sc) > length(shadow)) shadow = sc
    }
    # Try every matching alias, longest scope and key first, and keep the
    # first that lands on a real file. A paths entry is a LIST of fallbacks
    # in TypeScript, so the first candidate not existing is normal.
    best = -1; bestlen = -1
    for (i = 1; i <= nalias; i++) {
      if (alias_scope[i] != "" && index(from, alias_scope[i] "/") != 1) continue
      if (shadow != "" && alias_scope[i] != shadow) continue
      if (alias_wild[i]) { if (index(mod, alias_from[i]) != 1) continue }
      else               { if (mod != alias_from[i]) continue }
      L = length(alias_scope[i]) * 1000 + length(alias_from[i])
      if (L < bestlen) continue
      base = alias_to[i] (alias_wild[i] ? substr(mod, length(alias_from[i]) + 1) : "")
      if (alias_scope[i] != "") base = alias_scope[i] "/" base
      hit = try_path_js(norm(base))
      if (hit != "") { bestlen = L; best = i; besthit = hit }
    }
    if (best > 0) { setbind(from, besthit, "INFERRED", 1); emit(from, besthit, lang, form, "INFERRED", lno); return }
    # baseUrl-style bare specifier that is really an internal path.
    if (index(mod, "node:") == 1) { drop(from, mod, "stdlib", lno); return }
    hit = try_path_js(norm(mod))
    if (hit == "") hit = try_path_js(norm("src/" mod))
    if (hit != "") { setbind(from, hit, "INFERRED", 0); emit(from, hit, lang, form, "INFERRED", lno); return }
    drop(from, mod, "external-package", lno); return
  }

  if (lang == "py") {
    # A name that does not resolve as a submodule (form "from-import-
    # submodule") is a binding, not a drop - the §16c fix. The drop for M
    # itself (any other form using this same relative/absolute resolution)
    # still gets written below.
    if (mod ~ /^\./) {
      up = 0
      while (substr(mod, up + 1, 1) == ".") up++
      rest = substr(mod, up + 1)
      base = d
      for (i = 2; i <= up; i++) {
        if (base == "") { if (form != "from-import-submodule") drop(from, mod, "climbs-above-package", lno); return }
        base = dirname(base)
      }
      # Landing ON the repo root means the climb went one level past the
      # top-level package - Python raises for this. Resolving it anyway lands
      # on whatever decoy happens to sit at the root.
      if (base == "" && up > 1) { if (form != "from-import-submodule") drop(from, mod, "climbs-above-package", lno); return }
      gsub(/\./, "/", rest)
      base = norm(base (rest == "" ? "" : "/" rest))
      if (base == "") { if (form != "from-import-submodule") drop(from, mod, "climbs-above-root", lno); return }
      hit = try_path(base, "py")
      if (hit != "") { setbind(from, hit, "EXTRACTED", 0); emit(from, hit, lang, form, "EXTRACTED", lno); return }
      if (form != "from-import-submodule") drop(from, mod, "relative-path-has-no-file", lno); return
    }
    base = mod
    gsub(/\./, "/", base)
    hit = try_path(base, "py")
    if (hit == "") hit = try_path("src/" base, "py")
    # Only a DOTTED name may fall back to a suffix match. A bare `import
    # logging` is the stdlib, and a repo with any logging.py in it would
    # otherwise acquire an edge to it from every file in the tree.
    if (hit == "" && index(base, "/") > 0) hit = try_suffix(base, "py")
    if (hit != "") {
      conf = (hit == base ".py" || hit == base "/__init__.py") ? "EXTRACTED" : "INFERRED"
      setbind(from, hit, conf, 0)
      emit(from, hit, lang, form, conf, lno); return
    }
    if (form != "from-import-submodule") drop(from, mod, (ambiguous ? "ambiguous-name" : "external-or-stdlib"), lno)
    return
  }

  if (lang == "go") {
    # Longest matching module scope wins, so a nested module resolves against
    # its own go.mod rather than the outer one.
    gbest = -1; gbestlen = -1
    for (i = 1; i <= ngomod; i++) {
      if (gomod_scope[i] != "" && index(from, gomod_scope[i] "/") != 1) continue
      if (index(mod, gomod_path[i]) != 1) continue
      # The prefix must end at a path boundary. Without this a sibling module
      # named "example.com/app-contrib" matches the module "example.com/app"
      # and its imports get resolved into the wrong tree.
      nxt = substr(mod, length(gomod_path[i]) + 1, 1)
      if (nxt != "" && nxt != "/") continue
      L = length(gomod_scope[i]) * 1000 + length(gomod_path[i])
      if (L > gbestlen) { gbestlen = L; gbest = i }
    }
    if (gbest > 0) {
      base = substr(mod, length(gomod_path[gbest]) + 1)
      sub(/^\//, "", base)
      base = norm((gomod_scope[gbest] == "" ? "" : gomod_scope[gbest] "/") base)
      if (base != "" && dirn[base] > 0) {
        n = 0
        for (i = 1; i <= dirn[base]; i++) {
          if (extof(dirf[base, i]) != "go") continue
          if (++n > maxfan) break
          emit(from, dirf[base, i], lang, form, "EXTRACTED", lno)
        }
        if (n > 0) return
      }
      drop(from, mod, "module-path-has-no-dir", lno); return
    }
    if (mod !~ /\./) { drop(from, mod, "stdlib", lno); return }
    drop(from, mod, "external-package", lno); return
  }

  if (lang == "jvm") {
    if (mod ~ /\*$/) {
      base = mod
      sub(/\.\*$/, "", base)
      gsub(/\./, "/", base)
      n = 0
      for (key in dirn) {
        if (key != base && index(key "/", "/" base "/") == 0 && key !~ ("/" base "$")) continue
        for (i = 1; i <= dirn[key]; i++) {
          if (lang_of(extof(dirf[key, i])) != "jvm") continue
          if (++n > maxfan) break
          emit(from, dirf[key, i], lang, "import-wildcard", "INFERRED", lno)
        }
      }
      if (n > 0) return
      # No such package: `import static a.b.C.*` names the members of a
      # TYPE, so retry the same path as a type.
      hit = try_suffix(base, "jvm")
      if (hit != "") { emit(from, hit, lang, "import-static-wildcard", "INFERRED", lno); return }
      drop(from, mod, "wildcard-package-not-found", lno); return
    }
    base = mod
    gsub(/\./, "/", base)
    hit = try_suffix(base, "jvm")
    if (hit != "") { emit(from, hit, lang, form, "EXTRACTED", lno); return }
    # `import static a.b.C.MEMBER` and `import a.b.Outer.Nested` both name
    # something inside a type, so the file is one segment up.
    # `a.b.Outer.Nested` and `import static a.b.C.MEMBER` name something
    # inside a type, so the file is one or more segments up.
    #
    # Only drop a segment that starts with a CAPITAL. A lowercase tail is a
    # top-level function or property of a package, which no single file
    # owns; dropping it lands on whatever same-named file sits beside the
    # package directory, and that edge is fiction.
    seg = base
    while (seg ~ /\/[A-Z][^\/]*$/) {
      sub(/\/[^\/]*$/, "", seg)
      if (seg == "" || seg !~ /\//) break
      hit = try_suffix(seg, "jvm")
      if (hit != "") { emit(from, hit, lang, form, "INFERRED", lno); return }
    }
    drop(from, mod, (ambiguous ? "ambiguous-name" : "external-or-jdk"), lno); return
  }

  if (lang == "cs") {
    base = mod
    gsub(/\./, "/", base)
    hit = try_suffix(base, "cs")
    if (hit != "") { emit(from, hit, lang, form, "INFERRED", lno); return }
    drop(from, mod, (ambiguous ? "ambiguous-name" : "using-is-a-namespace-not-a-file"), lno); return
  }

  if (lang == "proj") {
    base = norm(d "/" mod)
    if (base != "" && accept(base)) { emit(from, base, lang, form, "EXTRACTED", lno); return }
    drop(from, mod, "projectreference-has-no-file", lno); return
  }

  if (lang == "rs") {
    if (form == "mod") {
      hit = try_path(norm(d "/" mod), "rs")
      if (hit == "") hit = try_path(norm(stripext(from) "/" mod), "rs")
      if (hit != "") { emit(from, hit, lang, form, "EXTRACTED", lno); return }
      drop(from, mod, "mod-decl-has-no-file", lno); return
    }
    base = mod
    if (index(base, "crate::") == 1) {
      rest = substr(base, 8)
      gsub(/::/, "/", rest)
      for (i = 1; i <= ncrate; i++) {
        hit = try_path(norm(crateroot[i] "/" rest), "rs")
        if (hit == "") { seg = rest; if (sub(/\/[^\/]*$/, "", seg)) hit = try_path(norm(crateroot[i] "/" seg), "rs") }
        if (hit != "") { emit(from, hit, lang, form, "EXTRACTED", lno); return }
      }
      drop(from, mod, "crate-path-has-no-file", lno); return
    }
    if (index(base, "self::") == 1 || index(base, "super::") == 1) {
      up = (index(base, "super::") == 1) ? 1 : 0
      rest = base
      sub(/^(self|super)::/, "", rest)
      gsub(/::/, "/", rest)
      basedir = d
      if (up) basedir = dirname(basedir)
      hit = try_path(norm(basedir "/" rest), "rs")
      if (hit == "") { seg = rest; if (sub(/\/[^\/]*$/, "", seg)) hit = try_path(norm(basedir "/" seg), "rs") }
      if (hit != "") { emit(from, hit, lang, form, "EXTRACTED", lno); return }
      drop(from, mod, "relative-path-has-no-file", lno); return
    }
    drop(from, mod, "external-crate", lno); return
  }

  if (lang == "rb") {
    if (form == "require_relative") {
      hit = try_path(norm(d "/" mod), "rb")
      if (hit != "") { emit(from, hit, lang, form, "EXTRACTED", lno); return }
      drop(from, mod, "relative-path-has-no-file", lno); return
    }
    hit = try_path(norm("lib/" mod), "rb")
    if (hit == "") hit = try_suffix(mod ".rb", "rb")
    if (hit != "") { emit(from, hit, lang, form, "INFERRED", lno); return }
    drop(from, mod, (ambiguous ? "ambiguous-name" : "load-path-dependent"), lno); return
  }

  if (lang == "php") {
    if (form == "use" || form == "use-group") {
      # A `use` with no namespace separator is a trait use inside a class
      # body, not an import. Treating it as one invents an edge to whatever
      # file happens to be named after the trait.
      if (mod !~ /\\/) { drop(from, mod, "trait-use-not-an-import", lno); return }
      base = mod
      # ONE backslash. /\\\\/ is the regex for two of them, and a PHP
      # namespace separator is a single one, so nothing was ever replaced.
      gsub(/\\/, "/", base)
      sub(/^\//, "", base)
      # Longest PSR-4 prefix wins: with both "App/" -> src/ and
      # "App/Billing/" -> billing/ registered, the first match is the wrong
      # one half the time.
      best = -1; bestlen = -1
      for (i = 1; i <= nalias; i++) {
        if (index(base, alias_from[i]) != 1) continue
        if (length(alias_from[i]) > bestlen) { bestlen = length(alias_from[i]); best = i }
      }
      if (best > 0) {
        hit = try_path(norm(alias_to[best] substr(base, length(alias_from[best]) + 1)), "php")
        if (hit != "") { emit(from, hit, lang, form, "INFERRED", lno); return }
      }
      hit = try_suffix(base, "php")
      if (hit != "") { emit(from, hit, lang, form, "INFERRED", lno); return }
      drop(from, mod, (ambiguous ? "ambiguous-name" : "psr4-unmapped"), lno); return
    }
    hit = try_path(norm(d "/" mod), "php")
    if (hit == "") hit = try_path(norm(mod), "php")
    if (hit != "") { emit(from, hit, lang, form, "EXTRACTED", lno); return }
    drop(from, mod, "include-path-has-no-file", lno); return
  }

  if (lang == "c") {
    if (form == "include-local") {
      hit = try_path(norm(d "/" mod), "c")
      if (hit == "") hit = try_path(norm(mod), "c")
      if (hit == "") hit = try_path(norm("include/" mod), "c")
      if (hit == "") hit = try_path(norm("src/" mod), "c")
      if (hit == "") hit = try_suffix(mod, "c")
      if (hit != "") { emit(from, hit, lang, form, "EXTRACTED", lno); return }
      drop(from, mod, "include-not-found", lno); return
    }
    # <angle> includes are the toolchain's. They resolve only against an
    # explicit include root, never by suffix: <memory> and <string.h> match
    # src/util/memory.hpp and src/util/string.h in a great many real repos,
    # and every one of those edges is fiction.
    hit = ""
    if (mod ~ /\//) {
      hit = try_path(norm("include/" mod), "c")
      if (hit == "") hit = try_path(norm(mod), "c")
    }
    if (hit != "") { emit(from, hit, lang, form, "INFERRED", lno); return }
    drop(from, mod, "system-header", lno); return
  }

  if (lang == "sh") {
    hit = try_path(norm(d "/" mod), "sh")
    if (hit == "") hit = try_path(norm(mod), "sh")
    if (hit != "") { emit(from, hit, lang, form, "EXTRACTED", lno); return }
    drop(from, mod, "source-path-not-found", lno); return
  }
}

# --- extraction --------------------------------------------------------------
# `re` is a STRING, never a /literal/. A regex literal in an argument position
# is evaluated as ($0 ~ /literal/) and arrives here as 0 or 1, which then
# matches any line containing a "0" or a "1" - silently, and everywhere.
function grab(line, re, lead, trail,   s) {
  if (!match(line, re)) return ""
  s = substr(line, RSTART + lead, RLENGTH - lead - trail)
  return s
}

# --- bindings.tsv: which name an import binds, and to which resolved file --
# resolve() sets bindto/bindconf/bindalias below on every JS/TS or Python call
# it handles (regardless of whether emit() itself dedups the edge, since
# emit() returning early is exactly what would otherwise hide the target from
# the caller). setbind() is the one place that decides a candidate counts: a
# self-edge (hit == from) is never emitted by emit() either, so recording one
# here would leave a bindings row with no matching imports.tsv edge - the one
# invariant bindings.tsv promises never to break.
function setbind(f, t, conf, alias) {
  if (t != "" && t != f) { bindto = t; bindconf = conf; bindalias = alias }
  else { bindto = ""; bindconf = ""; bindalias = 0 }
}

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

# Comma-joined subset of type,dynamic,cjs,alias, always in that order.
function mkflags(tf, dy, cj, al,   out) {
  out = ""
  if (tf) out = "type"
  if (dy) out = out (out == "" ? "" : ",") "dynamic"
  if (cj) out = out (out == "" ? "" : ",") "cjs"
  if (al) out = out (out == "" ? "" : ",") "alias"
  return out
}

function bindrow(bfrom, bline, bto, blocal, bimported, bkind, bconf, bflags, bmodule) {
  if (bindings == "") return
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", bfrom, bline, bto, blocal, bimported, bkind, bconf, bflags, bmodule >> bindings
}

# The last starting position of literal (non-regex) `t` in `s`, or 0. Used to
# find which of two keywords sits closer to the end of a string - no lookahead
# in POSIX ERE, so this is done without one.
function lastindex(s, t,   p, r, i) {
  r = 0; i = 1
  while ((p = index(substr(s, i), t)) > 0) {
    r = i + p - 1
    i = r + length(t)
  }
  return r
}

# Which of "import"/"export" sits closer to the end of `s` (a prefix with no
# quotes in it, so no other candidate can hide behind one), and its position
# in the global `kwpos` - together they say where the clause that actually
# owns the upcoming `from` begins.
function js_lastkw(s,   pi, pe) {
  pi = lastindex(s, "import")
  pe = lastindex(s, "export")
  if (pi == 0 && pe == 0) { kwpos = 0; return "" }
  if (pi > pe) { kwpos = pi; return "import" }
  kwpos = pe; return "export"
}

# Which PHYSICAL line a character position in the current (possibly joined)
# `code` came from. Position 1 is not always on the line the join started on:
# in the trap ("export const a = 1" glues onto the next line's real import,
# see js_lastkw()'s caller), the keyword js_lastkw() finds sits on whichever
# later line actually holds it, and that line - not the join's start - is
# what a bindings row must report.
function js_lineof(pos,   i, cum) {
  cum = 0
  for (i = 1; i <= pcount; i++) {
    cum += plen[i]
    if (pos <= cum) return pline[i]
    cum += 1
  }
  return pline[pcount]
}

# One Python `from M import a, b as c[, ...]` name list, already joined to a
# single logical line (the parenthesised and backslash-continued forms both
# land here once their names are on one string). mto/mconf are M's OWN
# resolution (the "from-import" edge); a name that resolves as a submodule of
# M is a MODULE binding to that submodule, one that does not is a NAMED
# binding to M's file - the §16c fix: unresolved.tsv keeps the drop for M
# itself but not one more for every name that is not a submodule.
function py_submodule_names(bfrom, lno, bline, mbase, mto, mconf, namestext,
                             nn, NP, i, raw, impname, aliasname) {
  nn = split(namestext, NP, /,/)
  for (i = 1; i <= nn; i++) {
    raw = trim(NP[i])
    if (raw == "") continue
    if (raw == "*") { bindrow(bfrom, bline, mto, "", "*", "star", mconf, "", mbase); continue }
    impname = raw
    sub(/[ \t]+as[ \t]+.*$/, "", impname)
    gsub(/[ \t]/, "", impname)
    if (impname == "" || impname == "*") continue
    aliasname = impname
    if (raw ~ /[ \t]+as[ \t]+/) { aliasname = raw; sub(/^.*[ \t]+as[ \t]+/, "", aliasname); gsub(/[ \t]/, "", aliasname) }
    resolve(bfrom, "py", mbase (mbase ~ /\.$/ ? "" : ".") impname, "from-import-submodule", lno)
    if (bindto != "") bindrow(bfrom, bline, bindto, aliasname, "*", "module", bindconf, "", mbase)
    else bindrow(bfrom, bline, mto, aliasname, impname, "named", mconf, "", mbase)
  }
}

# Strip a clause-wide `type` prefix (`import type {...}`, `import type D`),
# leaving `type` alone as an actual default-import name (`import type from
# 'm'`) since then nothing follows it. Sets the global `typeall`.
function strip_typeall(clause,   save) {
  typeall = 0
  save = clause
  if (clause ~ /^type[ \t]+/) {
    sub(/^type[ \t]+/, "", clause)
    if (clause == "") clause = save
    else typeall = 1
  }
  return clause
}

# The text of a JS/TS import/export clause between the keyword and `from`:
# a default name, a `{ ... }` group, a `* as ns`, or a combination. Reads
# bindto/bindconf/bindalias, already set by the resolve() call for this same
# statement's module, and writes every name the clause binds.
function js_bind_clause(bfrom, bline, clause, reexport, modtext,
                         dpart, bpart, rest, ns, hasas, nb, EP, i, raw, tf,
                         impname, aliasname, kind) {
  clause = trim(strip_typeall(trim(clause)))
  if (clause == "") return

  if (index(clause, "{") > 0) {
    dpart = clause
    sub(/\{.*$/, "", dpart)
    gsub(/[ \t,]+$/, "", dpart)
    bpart = clause
    sub(/^[^{]*\{/, "", bpart)
    sub(/\}.*$/, "", bpart)
  } else if (index(clause, "*") > 0) {
    dpart = clause
    sub(/\*.*$/, "", dpart)
    gsub(/[ \t,]+$/, "", dpart)
    bpart = ""
    rest = clause
    sub(/^[^*]*\*/, "", rest)
    hasas = 0
    if (match(rest, /^[ \t]*as[ \t]+[A-Za-z_$][A-Za-z0-9_$]*/)) {
      hasas = 1
      ns = substr(rest, RSTART, RLENGTH)
      sub(/^[ \t]*as[ \t]+/, "", ns)
    }
    if (hasas)
      bindrow(bfrom, bline, bindto, ns, "*", (reexport ? "reexport-namespace" : "namespace"), bindconf, mkflags(typeall, 0, 0, bindalias), modtext)
    else if (reexport)
      bindrow(bfrom, bline, bindto, "", "*", "reexport-star", bindconf, mkflags(typeall, 0, 0, bindalias), modtext)
  } else {
    dpart = clause
    bpart = ""
  }

  if (dpart != "" && !reexport)
    bindrow(bfrom, bline, bindto, dpart, "default", "default", bindconf, mkflags(typeall, 0, 0, bindalias), modtext)

  if (bpart != "") {
    nb = split(bpart, EP, /,/)
    for (i = 1; i <= nb; i++) {
      raw = trim(EP[i])
      if (raw == "") continue
      tf = typeall
      if (!tf && raw ~ /^type[ \t]+/) { tf = 1; sub(/^type[ \t]+/, "", raw); raw = trim(raw) }
      impname = raw
      sub(/[ \t]+as[ \t]+.*$/, "", impname)
      gsub(/[ \t]/, "", impname)
      if (impname == "") continue
      aliasname = impname
      if (raw ~ /[ \t]+as[ \t]+/) { aliasname = raw; sub(/^.*[ \t]+as[ \t]+/, "", aliasname); gsub(/[ \t]/, "", aliasname) }
      kind = reexport ? "reexport" : (impname == "default" ? "default" : "named")
      bindrow(bfrom, bline, bindto, aliasname, impname, kind, bindconf, mkflags(tf, 0, 0, bindalias), modtext)
    }
  }
}

# What a require()/import() call's return value is bound to, read from the
# code immediately BEFORE the call on the same statement (anchored at the end,
# so a trap glued onto the front of the same buffer - two statements joined by
# a missing semicolon - cannot fool it: only the tail immediately before the
# call matters). flavor is "cjs" or "dynamic", it becomes the row's flag.
function js_bind_call(bfrom, bline, head, flavor, modtext,
                       t, local2, destr, n, EP, i, raw, key, val) {
  t = head
  # TS import-equals: `import x = require(...)`.
  if (flavor == "cjs" && match(t, /import[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=[ \t]*$/)) {
    local2 = substr(t, RSTART, RLENGTH)
    sub(/^import[ \t]+/, "", local2); sub(/[ \t]*=[ \t]*$/, "", local2)
    bindrow(bfrom, bline, bindto, local2, "*", "module", bindconf, mkflags(0, flavor == "dynamic", flavor == "cjs", bindalias), modtext)
    return
  }
  if (match(t, /(const|let|var)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=[ \t]*(await[ \t]+)?[ \t]*$/)) {
    local2 = substr(t, RSTART, RLENGTH)
    sub(/^(const|let|var)[ \t]+/, "", local2)
    sub(/[ \t]*=.*$/, "", local2)
    bindrow(bfrom, bline, bindto, local2, "*", "module", bindconf, mkflags(0, flavor == "dynamic", flavor == "cjs", bindalias), modtext)
    return
  }
  if (match(t, /(const|let|var)[ \t]*\{[^}]*\}[ \t]*=[ \t]*(await[ \t]+)?[ \t]*$/)) {
    destr = substr(t, RSTART, RLENGTH)
    sub(/^[^{]*\{/, "", destr); sub(/\}.*$/, "", destr)
    n = split(destr, EP, /,/)
    for (i = 1; i <= n; i++) {
      raw = trim(EP[i])
      if (raw == "") continue
      key = raw; val = raw
      if (raw ~ /:/) { sub(/:.*$/, "", key); sub(/^[^:]*:/, "", val) }
      gsub(/[ \t]/, "", key); gsub(/[ \t]/, "", val)
      if (key == "") continue
      bindrow(bfrom, bline, bindto, val, key, "named", bindconf, mkflags(0, flavor == "dynamic", flavor == "cjs", bindalias), modtext)
    }
    return
  }
  bindrow(bfrom, bline, bindto, "", "*", "module", bindconf, mkflags(0, flavor == "dynamic", flavor == "cjs", bindalias), modtext)
}

# One Python import statement. Split out so a line carrying several of them,
# separated by semicolons, can be handled one at a time. `bline` is the line
# bindings.tsv reports for this statement - the same as `lno` here, since
# py_stmt only ever runs on a single already-complete logical line; the
# parenthesised and backslash-continued forms are assembled in scan() instead
# and call py_submodule_names() directly with their own remembered start line.
function py_stmt(from, code, lno, bline,   m, names, mto, mconf, n, P, i, raw, impname, aliasname) {
  if (code ~ /^[ \t]*from[ \t]+[.A-Za-z_]/) {
    m = code
    sub(/^[ \t]*from[ \t]+/, "", m)
    names = m
    sub(/[ \t].*$/, "", m)
    mto = ""; mconf = ""
    if (m != "") { resolve(from, "py", m, "from-import", lno); mto = bindto; mconf = bindconf }
    # `from . import ingest, report` names submodules. The package edge is
    # real too - importing it runs __init__ - so both are emitted.
    if (names ~ /[ \t]import[ \t]/) {
      sub(/^[^ \t]*[ \t]+import[ \t]+/, "", names)
      sub(/#.*$/, "", names); gsub(/[()]/, "", names)
      py_submodule_names(from, lno, bline, m, mto, mconf, names)
    }
    return
  }
  if (code ~ /^[ \t]*import[ \t]+[A-Za-z_.]/) {
    m = code
    sub(/^[ \t]*import[ \t]+/, "", m)
    # `import a as b, c` - split on commas FIRST, then strip ` as NAME` per
    # element (and keep the alias as `local`): stripping the whole tail at
    # "as" before splitting throws away every name after the aliased one.
    n = split(m, P, /,/)
    for (i = 1; i <= n; i++) {
      raw = trim(P[i])
      if (raw == "") continue
      impname = raw
      sub(/[ \t]+as[ \t]+.*$/, "", impname)
      gsub(/[ \t]/, "", impname)
      if (impname == "") continue
      aliasname = impname
      if (raw ~ /[ \t]+as[ \t]+/) { aliasname = raw; sub(/^.*[ \t]+as[ \t]+/, "", aliasname); gsub(/[ \t]/, "", aliasname) }
      resolve(from, "py", impname, "import", lno)
      bindrow(from, bline, bindto, aliasname, "*", "module", bindconf, "", impname)
    }
  }
}

function scan(from,   lang, line, lno, full, code, m, pend, i) {
  lang = lang_of(extof(from))
  if (lang == "") return
  full = (from ~ /^\//) ? from : root "/" from
  blockstate = 0; blockq = ""; ingo = 0; prevjvm = ""; pyopen = ""; pcount = 0
  lno = 0
  pend = ""
  while ((getline line < full) > 0) {
    lno++
    if (lno == 1) sub(/^\357\273\277/, "", line)   # UTF-8 BOM
    sub(/\r$/, "", line)                             # a file saved on Windows
    if (lno > 4000) break          # a generated bundle has nothing to say
    # A TypeScript triple-slash directive is a comment by syntax and a
    # dependency by meaning, so it must be read before comments are removed.
    if (lang == "js" && line ~ /^[ \t]*\/\/\/[ \t]*<reference/) {
      if (match(line, /path[ \t]*=[ \t]*["'"'"'][^"'"'"']+["'"'"']/)) {
        m = substr(line, RSTART, RLENGTH)
        sub(/^[^"'"'"']*["'"'"']/, "", m); sub(/["'"'"']$/, "", m)
        resolve(from, lang, m, "reference-path", lno)
      }
      continue
    }
    code = decomment(line, lang)
    if (code ~ /^[ \t]*$/) continue
    rawcode = code

    # An import statement split across lines: join until the specifier lands.
    # `stmtline` is the line bindings.tsv reports for whatever statement is
    # current: the line this join STARTED on, remembered across every line it
    # takes to land, never the line it happens to finish on. pline[]/plen[]
    # remember where each joined-in physical line begins and how long its own
    # (pre-join) code was, so js_lineof() can map a position back to ITS
    # physical line - not every position in a joined buffer is on the line
    # the join started on: see js_lineof()'s own comment for why that matters.
    joined = 0
    if (pend != "") {
      pad = sprintf("%" (length(pend) + 1) "s", "")
      gsub(/ /, ".", pad)
      strmask = pad strmask
      code = pend " " code
      pend = ""
      joined = 1
    }
    if (!joined) { stmtline = lno; pcount = 0 }
    pcount++; pline[pcount] = lno; plen[pcount] = length(rawcode)

    if (lang == "js") {
      if (code ~ /^[ \t]*(import|export)[ \t]/ && code !~ /['"]/ && code !~ /;[ \t]*$/) { pend = code; continue }
      # `await import(` with the specifier on the following line.
      if (code ~ /import[ \t]*\([ \t]*$/) { pend = code; continue }
      m = grab(code, "^[ \t]*(import|export)[^'\"]*from[ \t]*['\"][^'\"]+['\"]", 0, 0)
      if (m != "") {
        fullmatch = m
        sub(/^[^'"]*['"]/, "", m); sub(/['"]$/, "", m)
        resolve(from, lang, m, "import", lno)
        # Find the clause's OWN keyword, not necessarily the line's first one:
        # a joined buffer can hold two statements (`export const a = 1` has no
        # quote and no semicolon, so it starts a pend too, and the next line's
        # real import lands glued onto its tail) - the keyword closest to
        # `from` is the one that owns this clause.
        head = fullmatch
        sub(/from[ \t]*['"][^'"]*['"][ \t]*$/, "", head)
        kw = js_lastkw(head)
        if (kw != "") js_bind_clause(from, js_lineof(kwpos), substr(head, kwpos + length(kw)), (kw == "export") ? 1 : 0, m)
      }
      m = grab(code, "^[ \t]*import[ \t]*['\"][^'\"]+['\"]", 0, 0)
      if (m != "") {
        sub(/^[^'"]*['"]/, "", m); sub(/['"]$/, "", m)
        resolve(from, lang, m, "import-side-effect", lno)
        bindrow(from, stmtline, bindto, "", "", "side-effect", bindconf, mkflags(0, 0, 0, bindalias), m)
      }
      # require(...) and import(...) are not anchored to the start of a line,
      # so they can and do appear inside template literals and quoted strings.
      # The mask says whether this occurrence is code.
      rest = code; off = 0
      while (match(rest, /require[ \t]*\([ \t]*['"][^'"]+['"]/)) {
        m = substr(rest, RSTART, RLENGTH)
        quoted = in_string(off + RSTART)
        head = substr(code, 1, off + RSTART - 1)
        callpos = off + RSTART
        off += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
        if (quoted) continue
        sub(/^[^'"]*['"]/, "", m); sub(/['"]$/, "", m)
        resolve(from, lang, m, "require", lno)
        js_bind_call(from, js_lineof(callpos), head, "cjs", m)
      }
      # `require.resolve("...")` is a dependency written the long way.
      rest = code; off = 0
      while (match(rest, /require\.resolve[ \t]*\([ \t]*['"][^'"]+['"]/)) {
        m = substr(rest, RSTART, RLENGTH)
        quoted = in_string(off + RSTART)
        off += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
        if (quoted) continue
        sub(/^[^'"]*['"]/, "", m); sub(/['"]$/, "", m)
        resolve(from, lang, m, "require-resolve", lno)
      }
      # A triple-slash reference is how a .d.ts is pulled in.
      if (match(code, /<reference[ \t]+path[ \t]*=[ \t]*['"][^'"]+['"]/)) {
        m = substr(code, RSTART, RLENGTH)
        sub(/^[^'"]*['"]/, "", m); sub(/['"]$/, "", m)
        resolve(from, lang, m, "reference-path", lno)
      }
      rest = code; off = 0
      while (match(rest, /import[ \t]*\([ \t]*['"][^'"]+['"]/)) {
        m = substr(rest, RSTART, RLENGTH)
        quoted = in_string(off + RSTART)
        head = substr(code, 1, off + RSTART - 1)
        callpos = off + RSTART
        off += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
        if (quoted) continue
        sub(/^[^'"]*['"]/, "", m); sub(/['"]$/, "", m)
        resolve(from, lang, m, "dynamic-import", lno)
        js_bind_call(from, js_lineof(callpos), head, "dynamic", m)
      }
      continue
    }

    if (lang == "py") {
      # A parenthesised or backslash-continued from-import: the names are on
      # the lines after the opener, and (for the parenthesised form) the
      # first physical line names none of them. pyparen tells the two
      # continuations apart, since they close on different conditions.
      if (pyopen != "") {
        t = code
        if (pyparen) { if (t ~ /\)/) { pyopen = ""; sub(/\).*$/, "", t) } }
        else if (t !~ /\\[ \t]*$/) pyopen = ""
        else sub(/\\[ \t]*$/, "", t)
        py_submodule_names(from, lno, pyline, pybase, pymto, pymconf, t)
        continue
      }
      if (code ~ /^[ \t]*from[ \t].*import[ \t]*\([ \t]*$/) {
        pybase = code
        sub(/^[ \t]*from[ \t]+/, "", pybase)
        sub(/[ \t].*$/, "", pybase)
        pymto = ""; pymconf = ""
        if (pybase != "") { resolve(from, lang, pybase, "from-import", lno); pymto = bindto; pymconf = bindconf }
        pyline = stmtline
        pyopen = 1; pyparen = 1
        continue
      }
      # `from app.util.text import slugify, \` continues on the next
      # physical line(s), any number of them - join before parsing so every
      # name is seen, the same way the parenthesised form already does.
      if (code ~ /^[ \t]*from[ \t].*import[ \t]+.*\\[ \t]*$/) {
        pybase = code
        sub(/^[ \t]*from[ \t]+/, "", pybase)
        names = pybase
        sub(/[ \t].*$/, "", pybase)
        pymto = ""; pymconf = ""
        if (pybase != "") { resolve(from, lang, pybase, "from-import", lno); pymto = bindto; pymconf = bindconf }
        pyline = stmtline
        sub(/^[^ \t]*[ \t]+import[ \t]+/, "", names)
        sub(/\\[ \t]*$/, "", names)
        py_submodule_names(from, lno, pyline, pybase, pymto, pymconf, names)
        pyopen = 1; pyparen = 0
        continue
      }
      # `import json; import app.util.reading` is two statements, and a
      # reader that takes only the first silently loses the second.
      nsemi = split(code, SC, /;/)
      for (i = 1; i <= nsemi; i++) py_stmt(from, SC[i], lno, stmtline)
      continue
    }

    if (lang == "go") {
      # `import ()` is legal and closes on its own line. A matcher that
      # opens grouped state here and waits for a line starting with `)`
      # never closes, and then every quoted string in the file is an import.
      if (code ~ /^[ \t]*import[ \t]*\(/) { ingo = (code ~ /\)/) ? 0 : 1 }
      else if (ingo && code ~ /\)/) { ingo = 0; continue }
      m = grab(code, "\"[^\"]+\"", 1, 1)
      if (m != "" && (ingo || code ~ /^[ \t]*import[ \t]/)) resolve(from, lang, m, "import", lno)
      continue
    }

    if (lang == "jvm") {
      # An old formatter wraps a long import after a dot. It is still one
      # declaration, and half of it resolves to nothing.
      if (code ~ /^[ \t]*import[ \t].*\.[ \t]*$/) {
        pend = code; sub(/[ \t]*$/, "", pend); prevjvm = ""; continue
      }
      # ...and the other half of the same wrap: a line that STARTS with the
      # dot, which on its own looks like nothing at all.
      if (code ~ /^[ \t]*\.[A-Za-z_]/ && prevjvm != "") {
        m = prevjvm code
        sub(/^[ \t]*import[ \t]+(static[ \t]+)?/, "", m)
        gsub(/[ \t]/, "", m); sub(/;.*$/, "", m)
        prevjvm = ""
        if (m != "") resolve(from, lang, m, "import", lno)
        continue
      }
      if (code ~ /^[ \t]*import[ \t]/ && code !~ /;/ && code !~ /\*/ && code ~ /[A-Za-z0-9_]$/) {
        prevjvm = code
      }
      if (code ~ /^[ \t]*import[ \t]/) {
        m = code
        sub(/[ \t]+as[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*$/, "", m)
        sub(/^[ \t]*import[ \t]+(static[ \t]+)?/, "", m)
        sub(/[ \t]*;.*$/, "", m); gsub(/[ \t]/, "", m)
        if (m != "") resolve(from, lang, m, "import", lno)
      }
      continue
    }

    if (lang == "cs") {
      if (code ~ /^[ \t]*(global[ \t]+)?using[ \t]/) {
        m = code
        sub(/^[ \t]*(global[ \t]+)?using[ \t]+(static[ \t]+)?/, "", m)
        sub(/[ \t]*;.*$/, "", m); gsub(/[ \t]/, "", m)
        if (m ~ /=/) sub(/^[^=]*=/, "", m)
        if (m != "") resolve(from, lang, m, "using", lno)
      }
      continue
    }

    if (lang == "proj") {
      m = grab(code, "ProjectReference[^>]*Include[ \t]*=[ \t]*\"[^\"]+\"", 0, 0)
      if (m != "") { sub(/^[^"]*"/, "", m); sub(/"$/, "", m); gsub(/\\/, "/", m); resolve(from, lang, m, "project-reference", lno) }
      continue
    }

    if (lang == "rs") {
      if (code ~ /^[ \t]*(pub[ \t]+)?mod[ \t]+[A-Za-z_]/ && code !~ /\{/) {
        m = code
        sub(/^[ \t]*(pub[ \t]+)?mod[ \t]+/, "", m)
        sub(/[ \t]*;.*$/, "", m); gsub(/[ \t]/, "", m)
        if (m != "") resolve(from, lang, m, "mod", lno)
        continue
      }
      if (code ~ /^[ \t]*(pub[ \t]+)?use[ \t]/) {
        m = code
        sub(/^[ \t]*(pub[ \t]+)?use[ \t]+/, "", m)
        sub(/[ \t]*;.*$/, "", m); gsub(/[ \t]/, "", m)
        sub(/\{.*$/, "", m); sub(/::\*$/, "", m); sub(/::$/, "", m)
        if (m != "") resolve(from, lang, m, "use", lno)
      }
      continue
    }

    if (lang == "rb") {
      rest = code; off = 0; found = 0
      while (match(rest, "require_relative[ \t]*\\(?[ \t]*['\"][^'\"]+['\"]")) {
        m = substr(rest, RSTART, RLENGTH)
        quoted = in_string(off + RSTART)
        off += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
        if (quoted) continue
        sub(/^[^'"]*['"]/, "", m); sub(/['"]$/, "", m)
        resolve(from, lang, m, "require_relative", lno)
        found = 1
      }
      if (found) continue
      if (match(code, "^[ \t]*require[ \t]*\\(?[ \t]*['\"][^'\"]+['\"]") && !in_string(RSTART)) {
        m = substr(code, RSTART, RLENGTH)
        sub(/^[^'"]*['"]/, "", m); sub(/['"]$/, "", m)
        resolve(from, lang, m, "require", lno)
      }
      continue
    }

    if (lang == "php") {
      # A `require_once '...'` written inside a string constant names a
      # real file and reads exactly like the real thing.
      if (match(code, "(require|include)(_once)?[ \t]*\\(?[ \t]*(__DIR__[ \t]*\\.[ \t]*)?['\"][^'\"]+['\"]") && !in_string(RSTART)) {
        m = substr(code, RSTART, RLENGTH)
        sub(/^[^'"]*['"]/, "", m); sub(/['"]$/, "", m); sub(/^\//, "", m)
        resolve(from, lang, m, "require", lno); continue
      }
      if (code ~ /^[ \t]*use[ \t]+[A-Za-z_\\]/) {
        m = code
        sub(/^[ \t]*use[ \t]+(function[ \t]+|const[ \t]+)?/, "", m)
        sub(/[ \t]*;.*$/, "", m); sub(/[ \t]+as[ \t].*$/, "", m); gsub(/[ \t]/, "", m)
        # Group use: `use App\Metering\{Invoice, Receipt};` is several
        # imports sharing a prefix.
        if (m ~ /\{/) {
          pfx = m; sub(/\{.*$/, "", pfx)
          grp = m; sub(/^[^{]*\{/, "", grp); sub(/\}.*$/, "", grp)
          ng = split(grp, GP, /,/)
          for (i = 1; i <= ng; i++) {
            sub(/[ \t]+as[ \t].*$/, "", GP[i]); gsub(/[ \t]/, "", GP[i])
            if (GP[i] != "") resolve(from, lang, pfx GP[i], "use-group", lno)
          }
        } else if (m != "") resolve(from, lang, m, "use", lno)
      }
      continue
    }

    if (lang == "c") {
      m = grab(code, "^[ \t]*#[ \t]*include[ \t]*\"[^\"]+\"", 0, 0)
      if (m != "") { sub(/^[^"]*"/, "", m); sub(/"$/, "", m); resolve(from, lang, m, "include-local", lno); continue }
      m = grab(code, "^[ \t]*#[ \t]*include[ \t]*<[^>]+>", 0, 0)
      if (m != "") { sub(/^[^<]*</, "", m); sub(/>$/, "", m); resolve(from, lang, m, "include-system", lno) }
      continue
    }

    if (lang == "sh") {
      m = grab(code, "^[ \t]*(\\.|source)[ \t]+[\"']?[A-Za-z0-9_./$-]+", 0, 0)
      if (m != "") {
        sub(/^[ \t]*(\.|source)[ \t]+/, "", m); gsub(/["']/, "", m)
        gsub(/\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\//, "", m)
        if (m != "" && m !~ /^-/) resolve(from, lang, m, "source", lno)
      }
      continue
    }
  }
  close(full)
}

BEGIN {
  if (maxfan == "" || maxfan + 0 < 1) maxfan = 40
  nedges = 0; ndropped = 0; nalias = 0; ncrate = 0

  while ((getline line < filelist) > 0) {
    if (line == "") continue
    index_file(line)
    if (line ~ /(^|\/)(lib|main)\.rs$/) crateroot[++ncrate] = dirname(line)
  }
  close(filelist)

  ngomod = 0
  if (gomods != "") {
    while ((getline line < gomods) > 0) {
      if (line == "") continue
      split(line, G, "\t")
      if (G[2] == "") continue
      ngomod++
      gomod_scope[ngomod] = G[1]
      gomod_path[ngomod]  = G[2]
    }
    close(gomods)
  }

  if (aliases != "") {
    while ((getline line < aliases) > 0) {
      if (line == "") continue
      split(line, A, "\t")
      if (A[2] == "" || A[3] == "") continue
      nalias++
      alias_scope[nalias] = A[1]
      alias_from[nalias]  = A[2]
      alias_to[nalias]    = A[3]
      alias_wild[nalias]  = (A[4] == "0") ? 0 : 1
      alias_own[nalias]   = (A[5] == "1") ? 1 : 0
      if (alias_own[nalias]) ownscope[A[1]] = 1
    }
    close(aliases)
  }
}

{ if ($0 != "") scan($0) }

END {
  # Header pairing: changing foo.h almost always means recompiling foo.c, and
  # no #include in either file says so.
  for (p in exact) {
    e = extof(p)
    if (e != "h" && e != "hpp" && e != "hh" && e != "hxx") continue
    b = stripext(p)
    split(".c .cpp .cc .cxx .m .mm", CE, " ")
    for (i = 1; i <= 6; i++) if (CE[i] != "" && (b CE[i]) in exact)
      emit(b CE[i], p, "c", "header-pair", "EXTRACTED", "0")
  }
  printf "code-graph: %d edges, %d imports unresolved\n", nedges, ndropped > "/dev/stderr"
}
