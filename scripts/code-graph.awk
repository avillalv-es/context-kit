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
  bindto = ""; bindconf = ""; bindalias = 0; bindself = 0
  d = dirname(from)

  if (lang == "js") {
    if (mod ~ /^\.\.?\//) {
      base = norm(d "/" mod)
      if (base == "") { drop(from, mod, "climbs-above-root", lno); return }
      hit = try_path_js(base)
      if (hit != "") { emit(from, hit, lang, form, "EXTRACTED", lno); setbind(from, hit, form, "EXTRACTED", 0); return }
      drop(from, mod, "relative-path-has-no-file", lno); return
    }
    if (mod ~ /^\//) {
      hit = try_path_js(norm(mod))
      if (hit != "") { emit(from, hit, lang, form, "EXTRACTED", lno); setbind(from, hit, form, "EXTRACTED", 0); return }
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
    # The bindings `alias` flag is reserved for a tsconfig/jsconfig paths
    # entry or a package.json imports entry - never a composer PSR-4 one
    # that happens to also match: aliases.tsv tags its source, and PSR-4
    # rows are "psr4", not "ts"/"pkg". This does not change WHICH file a
    # bare specifier resolves to, only whether the row says `alias`.
    if (best > 0) {
      emit(from, besthit, lang, form, "INFERRED", lno)
      setbind(from, besthit, form, "INFERRED", (alias_kind[best] == "psr4") ? 0 : 1)
      return
    }
    # baseUrl-style bare specifier that is really an internal path.
    if (index(mod, "node:") == 1) { drop(from, mod, "stdlib", lno); return }
    hit = try_path_js(norm(mod))
    if (hit == "") hit = try_path_js(norm("src/" mod))
    if (hit != "") { emit(from, hit, lang, form, "INFERRED", lno); setbind(from, hit, form, "INFERRED", 0); return }
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
      if (hit != "") { emit(from, hit, lang, form, "EXTRACTED", lno); setbind(from, hit, form, "EXTRACTED", 0); return }
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
      emit(from, hit, lang, form, conf, lno)
      setbind(from, hit, form, conf, 0)
      return
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
# resolve() sets bindto/bindconf/bindalias/bindself below on every JS/TS or
# Python call it handles (regardless of whether emit() itself dedups the
# edge, since emit() returning early is exactly what would otherwise hide the
# target from the caller). setbind() is the one place that decides a
# candidate counts: a self-edge (hit == from) is never emitted by emit()
# either, so recording one here would leave a bindings row with no matching
# imports.tsv edge - the one invariant bindings.tsv promises never to break.
# bindself distinguishes that (a target that WOULD have resolved, just to
# itself) from a genuine non-resolution, for a caller that needs to tell the
# two apart (see py_submodule_names()).
# conf is always THIS statement's OWN resolution, never emit()'s (emit()
# dedups on (from,to,form), so a second statement reaching the same edge by
# a different route - an alias next to a relative import to the same file,
# say - gets no imports.tsv row of its own, but its binding still reports
# its own conf, which can differ from the row imports.tsv shows).
function setbind(f, t, form, conf, alias) {
  if (t != "" && t != f) {
    bindto = t
    bindconf = conf
    bindalias = alias
    bindself = 0
  } else {
    bindto = ""; bindconf = ""; bindalias = 0
    bindself = (t != "") ? 1 : 0
  }
}

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

# A clause that does not parse as valid JS/TS text (prose caught by the
# same "from ... '...'" shape a .vue template can fall into, say) yields no
# bindings row at all - only a real identifier is ever bound to anything.
function js_is_ident(s) { return (s ~ /^[A-Za-z_$][A-Za-z0-9_$]*$/) ? 1 : 0 }

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

# True when `c` is not part of an identifier: not one of A-Za-z0-9_$, and not
# the start/end of the string either. A high-bit byte (part of a multi-byte
# UTF-8 identifier, or - under a multibyte-aware awk - a whole non-ASCII
# character read back by substr) is deliberately NOT in this set: only a
# small, fixed set of ASCII punctuation actually separates one token from the
# next in decommented JS source, so anything else counts as identifier text,
# never as a boundary.
function js_boundary(c) {
  if (c == "") return 1
  return (index(" \t\n!\"#%&'()*+,-./:;<=>?@[\\]^`{|}~", c) > 0)
}

# The last starting position of literal (non-regex) `t` in `s` where `t`
# stands as its own identifier - bounded by js_boundary() on both sides, so
# "import" inside "importMap" or "reimport" is skipped - or 0 if there is no
# such occurrence. Used to find which of two keywords sits closer to the end
# of a string; no lookahead in POSIX ERE, so this is done without one.
function lastindex(s, t,   p, r, i, cand, before, after) {
  r = 0; i = 1
  while ((p = index(substr(s, i), t)) > 0) {
    cand = i + p - 1
    before = (cand == 1) ? "" : substr(s, cand - 1, 1)
    after = substr(s, cand + length(t), 1)
    if (js_boundary(before) && js_boundary(after)) r = cand
    i = cand + length(t)
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
# A name that resolves as a submodule equal to `bfrom` ITSELF (a module
# importing one of its own siblings by the package's relative name, `from .
# import x` inside x.py) is still a MODULE binding, never falls back to a
# NAMED one against M's file: `x` really is the submodule x.py, that file
# just happens to be the one doing the importing, so bindself (not an empty
# bindto) is what says so - an empty bindto alone cannot tell "not a
# submodule" from "the submodule, but it's a self-edge" apart.
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
    else if (bindself) bindrow(bfrom, bline, "", aliasname, "*", "module", "", "", mbase)
    else bindrow(bfrom, bline, mto, aliasname, impname, "named", mconf, "", mbase)
  }
}

# One Python `import a, b as c[, ...]` name list, already joined to a single
# logical line (a backslash-continued plain `import` lands here once its
# names are on one string). Unlike py_submodule_names(), there is no shared
# base: each name resolves as its own, independent import.
function py_plain_names(bfrom, lno, bline, namestext,
                         n, P, i, raw, impname, aliasname) {
  n = split(namestext, P, /,/)
  for (i = 1; i <= n; i++) {
    raw = trim(P[i])
    if (raw == "") continue
    impname = raw
    sub(/[ \t]+as[ \t]+.*$/, "", impname)
    gsub(/[ \t]/, "", impname)
    if (impname == "") continue
    aliasname = impname
    if (raw ~ /[ \t]+as[ \t]+/) { aliasname = raw; sub(/^.*[ \t]+as[ \t]+/, "", aliasname); gsub(/[ \t]/, "", aliasname) }
    resolve(bfrom, "py", impname, "import", lno)
    bindrow(bfrom, bline, bindto, aliasname, "*", "module", bindconf, "", impname)
  }
}

# Strip a clause-wide `type` prefix (`import type {...}`, `import type D`,
# `import type{T}` - no space needed before a group opener), leaving `type`
# alone as an actual default-import name (`import type from 'm'`) since then
# nothing follows it at all. Sets the global `typeall`.
function strip_typeall(clause,   save) {
  typeall = 0
  if (clause ~ /^type[ \t]*[{*]/) { sub(/^type[ \t]*/, "", clause); typeall = 1; return clause }
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
                         impname, aliasname, kind, aftertype) {
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
    if (hasas) {
      if (js_is_ident(ns)) bindrow(bfrom, bline, bindto, ns, "*", (reexport ? "reexport-namespace" : "namespace"), bindconf, mkflags(typeall, 0, 0, bindalias), modtext)
    } else if (reexport) {
      bindrow(bfrom, bline, bindto, "", "*", "reexport-star", bindconf, mkflags(typeall, 0, 0, bindalias), modtext)
    }
  } else {
    dpart = clause
    bpart = ""
  }

  if (dpart != "" && !reexport && js_is_ident(dpart))
    bindrow(bfrom, bline, bindto, dpart, "default", "default", bindconf, mkflags(typeall, 0, 0, bindalias), modtext)

  if (bpart != "") {
    nb = split(bpart, EP, /,/)
    for (i = 1; i <= nb; i++) {
      raw = trim(EP[i])
      if (raw == "") continue
      tf = typeall
      # A per-name `type` prefix is a modifier only when a real name still
      # follows it. `type as t` has nothing after `type` but `as t` - "type"
      # there IS the imported name (aliased to t), not a marker.
      if (!tf && raw ~ /^type[ \t]+/) {
        aftertype = raw
        sub(/^type[ \t]+/, "", aftertype)
        if (aftertype !~ /^as[ \t]+/) { tf = 1; raw = trim(aftertype) }
      }
      impname = raw
      sub(/[ \t]+as[ \t]+.*$/, "", impname)
      gsub(/[ \t]/, "", impname)
      if (impname == "" || !js_is_ident(impname)) continue
      aliasname = impname
      if (raw ~ /[ \t]+as[ \t]+/) { aliasname = raw; sub(/^.*[ \t]+as[ \t]+/, "", aliasname); gsub(/[ \t]/, "", aliasname) }
      if (!js_is_ident(aliasname)) continue
      kind = reexport ? "reexport" : (impname == "default" ? "default" : "named")
      bindrow(bfrom, bline, bindto, aliasname, impname, kind, bindconf, mkflags(tf, 0, 0, bindalias), modtext)
    }
  }
}

# True when a require()/import() call's own closing ")" - the FIRST thing in
# `rest`, since the match this follows stopped at the module string's closing
# quote - is immediately followed by ".", "?.", "[", "!" or "(": reading a
# member off the result, calling it again, or non-null-asserting it, rather
# than end of statement, ";" or ",". Only a call that is the WHOLE
# initializer binds anything; one that is chained, called again, passed on
# or returned through a member/call never is. When ")" ends the line with
# nothing else after it, the same question is asked of the next CODE line
# (G1): `const b = require('./b')` then `  .default` on the following line
# chains it exactly as `.default` on the same line would.
function js_call_chained(rest, lno, lang,   t) {
  t = rest
  if (!sub(/^[ \t]*\)/, "", t)) return 0
  sub(/^[ \t]*/, "", t)
  if (t ~ /^[.?!([]/) return 1
  if (t != "") return 0
  return js_peek_chain(lno, lang)
}

# Peeks forward from physical line `lno0 + 1` (FL[], the whole-file buffer
# scan() slurped up front - see scan()'s own comment) for the next line whose
# code is non-blank once comments and strings are stripped, skipping blank
# and comment-only lines exactly as the main scan does, and reports whether
# ITS first character chains a require()/import() call the same way a same-
# line one would (see js_call_chained()) - except "!": that reads as the
# NEXT statement's own non-null-assertion or negation (`!function(){}()`),
# never as chaining onto THIS call, so only a same-line "!" counts (SPEC).
# decomment() mutates the shared blockstate/blockq/strmask as it goes - all
# three are saved and restored around every call here (F1), so this
# speculative look-ahead can never desync the real scan when it reaches
# these same lines for real, and never leaves the CALLER's own current
# line's string mask clobbered for the matches still to come on it.
function js_peek_chain(lno0, lang,   i, savebs, saveq, savesm, pc) {
  savebs = blockstate; saveq = blockq; savesm = strmask
  for (i = lno0 + 1; i <= nlines; i++) {
    pc = decomment(FL[i], lang)
    if (pc ~ /^[ \t]*$/) continue
    sub(/^[ \t]*/, "", pc)
    blockstate = savebs; blockq = saveq; strmask = savesm
    return (pc ~ /^[.?([]/) ? 1 : 0
  }
  blockstate = savebs; blockq = saveq; strmask = savesm
  return 0
}

# The 1-based position of the LAST top-level ',' in `s` - depth 0 in
# parens/brackets/braces, and outside any string body (per the global
# `strmask`, so `s` must be the current `code` or an unmodified prefix of
# it) - or 0 when there is none. A comma inside a nested call, array,
# object or string is never "top-level": `foo(a, cfg = require(...))`'s
# comma sits at depth 1 and is never returned here (item 9's `head`
# narrowing must never mistake a function call's argument list for a
# declarator list).
function js_last_top_comma(s,   n, i, c, depth, pos) {
  n = length(s); depth = 0; pos = 0
  for (i = 1; i <= n; i++) {
    if (substr(strmask, i, 1) == "S") continue
    c = substr(s, i, 1)
    if (c == "(" || c == "[" || c == "{") depth++
    else if (c == ")" || c == "]" || c == "}") depth--
    else if (c == "," && depth == 0) pos = i
  }
  return pos
}

# True when the top-level comma at `uptopos` in `s` sits inside a
# `(export)? (const|let|var)` statement's own declarator list: the nearest
# such keyword before it (word-bounded, via lastindex()) exists, and
# nothing at depth 0 between that keyword and `uptopos` ends the statement
# first (a ';'). Used by js_decl_head() (item 9) so a LATER declarator's
# require()/import() call - `const a = ..., cfg = require(...)` - is
# recognised as bound, while an unrelated comma (a function call's argument
# list, which js_last_top_comma() never even returns) or a plain
# reassignment with no governing keyword is not.
function js_decl_list_open(s, uptopos,   kwend, i, c, depth) {
  kwend = lastindex(substr(s, 1, uptopos), "const")
  i = lastindex(substr(s, 1, uptopos), "let"); if (i > kwend) kwend = i
  i = lastindex(substr(s, 1, uptopos), "var"); if (i > kwend) kwend = i
  if (kwend == 0) return 0
  depth = 0
  for (i = kwend; i <= uptopos; i++) {
    if (substr(strmask, i, 1) == "S") continue
    c = substr(s, i, 1)
    if (c == "(" || c == "[" || c == "{") depth++
    else if (c == ")" || c == "]" || c == "}") depth--
    else if (c == ";" && depth == 0) return 0
  }
  return 1
}

# js_bind_call()'s single-declarator patterns all anchor on seeing
# `(const|let|var)` directly before the bound name - true for the FIRST
# declarator, but a LATER one in the same statement (`const a = ..., cfg =
# require(...)`) has no keyword of its own right before it (item 9). Read
# `head` back only to the nearest top-level ',' (js_last_top_comma()); when
# a const/let/var statement really governs it (js_decl_list_open()), splice
# a synthetic keyword back on so js_bind_call()'s EXISTING patterns match
# the later declarator exactly as they would the first, unmodified. Falls
# back to `head` unchanged whenever there is no such comma, or it turns out
# not to be one.
function js_decl_head(head,   cpos) {
  cpos = js_last_top_comma(head)
  if (cpos == 0 || !js_decl_list_open(head, cpos)) return head
  return "const " substr(head, cpos + 1)
}

# What a require()/import() call's return value is bound to, read from the
# code immediately BEFORE the call on the same statement (anchored at the end,
# so a trap glued onto the front of the same buffer - two statements joined by
# a missing semicolon - cannot fool it: only the tail immediately before the
# call matters). `chained` (see js_call_chained()) forces the unbound row
# regardless of `head`. Every row - bound or not - reports `callline`, the
# physical line the require()/import() call itself sits on: that is the
# spec's rule for this form specifically, even when the declaration binding
# it spans several lines above the call (`const {\n a,\n} = require(...)`
# reports the require() line, not the `const {` line). flavor is "cjs" or
# "dynamic", it becomes the row's flag.
function js_bind_call(bfrom, callline, head, flavor, modtext, chained,
                       t, local2, destr, n, EP, i, raw, key, val, restname) {
  t = head
  if (!chained) {
    # TS import-equals: `import x = require(...)`.
    if (flavor == "cjs" && match(t, /import[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=[ \t]*$/)) {
      local2 = substr(t, RSTART, RLENGTH)
      sub(/^import[ \t]+/, "", local2); sub(/[ \t]*=[ \t]*$/, "", local2)
      if (js_is_ident(local2)) bindrow(bfrom, callline, bindto, local2, "*", "module", bindconf, mkflags(0, flavor == "dynamic", flavor == "cjs", bindalias), modtext)
      return
    }
    # `export`, when present, never changes the classification - only
    # `export { a }` (no `from`) and a declarator whose initializer is not
    # one of these forms give no row, and neither is this one.
    if (match(t, /(export[ \t]+)?(const|let|var)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=[ \t]*(await[ \t]+)?[ \t]*$/)) {
      local2 = substr(t, RSTART, RLENGTH)
      sub(/^(export[ \t]+)?(const|let|var)[ \t]+/, "", local2)
      sub(/[ \t]*=.*$/, "", local2)
      if (js_is_ident(local2)) bindrow(bfrom, callline, bindto, local2, "*", "module", bindconf, mkflags(0, flavor == "dynamic", flavor == "cjs", bindalias), modtext)
      return
    }
    if (match(t, /(export[ \t]+)?(const|let|var)[ \t]*\{[^}]*\}[ \t]*=[ \t]*(await[ \t]+)?[ \t]*$/)) {
      destr = substr(t, RSTART, RLENGTH)
      sub(/^[^{]*\{/, "", destr); sub(/\}.*$/, "", destr)
      n = split(destr, EP, /,/)
      for (i = 1; i <= n; i++) {
        raw = trim(EP[i])
        if (raw == "") continue
        if (raw ~ /^\.\.\./) {
          # `...rest` binds the module object of the remaining exports, same
          # as an unbound require() would - not a single named export.
          restname = raw
          sub(/^\.\.\./, "", restname); gsub(/[ \t]/, "", restname)
          if (js_is_ident(restname)) bindrow(bfrom, callline, bindto, restname, "*", "module", bindconf, mkflags(0, flavor == "dynamic", flavor == "cjs", bindalias), modtext)
          continue
        }
        key = raw; val = raw
        if (raw ~ /:/) { sub(/:.*$/, "", key); sub(/^[^:]*:/, "", val) }
        sub(/[ \t]*=.*$/, "", key)   # a default (`a = 1`): the name is `a`
        sub(/[ \t]*=.*$/, "", val)   # `b: c = 2`: the name is `c`
        gsub(/[ \t]/, "", key); gsub(/[ \t]/, "", val)
        if (key == "" || !js_is_ident(key) || !js_is_ident(val)) continue
        bindrow(bfrom, callline, bindto, val, key, "named", bindconf, mkflags(0, flavor == "dynamic", flavor == "cjs", bindalias), modtext)
      }
      return
    }
  }
  bindrow(bfrom, callline, bindto, "", "*", "module", bindconf, mkflags(0, flavor == "dynamic", flavor == "cjs", bindalias), modtext)
}

# One Python import statement. Split out so a line carrying several of them,
# separated by semicolons, can be handled one at a time. `bline` is the line
# bindings.tsv reports for this statement - the same as `lno` here, since
# py_stmt only ever runs on a single already-complete logical line; the
# parenthesised and backslash-continued forms are assembled in scan() instead
# and call py_submodule_names() directly with their own remembered start line.
function py_stmt(from, code, lno, bline,   m, names, mto, mconf) {
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
    # `import a as b, c` - py_plain_names() splits on commas FIRST, then
    # strips ` as NAME` per element (and keeps the alias as `local`):
    # stripping the whole tail at "as" before splitting throws away every
    # name after the aliased one.
    m = code
    sub(/^[ \t]*import[ \t]+/, "", m)
    py_plain_names(from, lno, bline, m)
  }
}

# The 1-based position of the first ';' in `s` that is not inside a string
# body, or 0 when there is none. `s` must be the CURRENT `code` (or an
# unmodified prefix of it), so the global `strmask` - decomment()'s own
# per-character string mask - still lines up with it position for position.
# A line with no ';' at all - almost every line - never needs the char-by-
# char scan below (PERF).
function py_unquoted_semi(s,   n, i) {
  if (index(s, ";") == 0) return 0
  n = length(s)
  for (i = 1; i <= n; i++)
    if (substr(s, i, 1) == ";" && substr(strmask, i, 1) != "S") return i
  return 0
}

# Split `s` (== the current `code`, so `strmask` aligns with it) on every ';'
# that is NOT inside a string body - same interface as split(): fills
# 1-indexed `arr`, returns the count. A ';' quoted inside a string
# (`HELP = "usage: a; from app import (x"`) never fakes a second statement
# out of the string's own text (R3). PERF: skip the char-by-char rebuild
# below when there is no ';' to begin with - true for almost every line, and
# without it a long line (a 200KB single-line Python file, say) rebuilds
# itself one character at a time on every call for nothing.
function py_split_semi(s, arr,   n, i, c, cur, cnt) {
  if (index(s, ";") == 0) { arr[1] = s; return 1 }
  n = length(s); cur = ""; cnt = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == ";" && substr(strmask, i, 1) != "S") { cnt++; arr[cnt] = cur; cur = "" }
    else cur = cur c
  }
  cnt++; arr[cnt] = cur
  return cnt
}

# Builds a string of `n` copies of the single character `ch` (n <= 0 gives
# "").
function repeat_char(n, ch,   s) {
  if (n <= 0) return ""
  s = sprintf("%" n "s", "")
  gsub(/ /, ch, s)
  return s
}

# The quote character ("'" or '"') still open at the END of `s` - already
# decommented, so any comment or triple-quoted block is already gone, and a
# string body's own characters are preserved verbatim either way - a plain
# single/double-quoted Python (or JS) string can itself be continued onto
# the next physical line with a trailing "\", and decomment() carries no
# memory of that across lines (F3): this replays its own single-line quote
# toggle (escape-aware) to recover which quote, if any, is left open.
# Returns "" when the line ends outside any such string.
function py_open_quote(s,   n, i, c, q) {
  n = length(s); q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") {
      if (c == "\\") { i++; continue }
      if (c == q) q = ""
      continue
    }
    if (c == "'" || c == "\"") q = c
  }
  return q
}

# The 1-based position of the first UNESCAPED `q` in `s`, or 0 when `s`
# never closes it (the same string carries on past this line too). Used to
# find where a string left open by the PREVIOUS line - see py_open_quote() -
# actually closes on a continuation line, escape-aware the same way.
function py_find_close(s, q,   n, i, c) {
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\") { i++; continue }
    if (c == q) return i
  }
  return 0
}

# One physical line's worth of Python statements (or a leftover tail of one,
# after a backslash continuation ended mid-line on an unquoted ';' - R4a).
# `import json; import app.util.reading` is two statements, and a reader
# that takes only the first silently loses the second - so this always
# splits on ';' first (outside strings, R3), even when only the LAST
# statement on the line turns out to open a continuation: `import os; from
# app.models import database, \` continues past the semicolon just as it
# would have starting the line, and `import os` beside it is still its own,
# complete statement.
function py_dispatch(pfrom, plang, pcode, plno,
                      nsemi, SC, i, seg, namepart, names, pclosed) {
  nsemi = py_split_semi(pcode, SC)
  for (i = 1; i <= nsemi; i++) {
    seg = SC[i]
    if (i == nsemi && seg ~ /^[ \t]*from[ \t].*import[ \t]*\(/) {
      pybase = seg
      sub(/^[ \t]*from[ \t]+/, "", pybase)
      namepart = pybase
      sub(/[ \t].*$/, "", pybase)
      pymto = ""; pymconf = ""
      if (pybase != "") { resolve(pfrom, plang, pybase, "from-import", plno); pymto = bindto; pymconf = bindconf }
      pyline = stmtline
      sub(/^[^ \t]*[ \t]+import[ \t]*\(/, "", namepart)
      pclosed = 0
      if (namepart ~ /\)/) { pclosed = 1; sub(/\).*$/, "", namepart) }
      # Inside brackets a trailing "\" is just a continuation, never a name
      # of its own (GAP2, opening-line variant).
      else sub(/\\[ \t]*$/, "", namepart)
      if (namepart != "") py_submodule_names(pfrom, plno, pyline, pybase, pymto, pymconf, namepart)
      pyplain = 0
      if (!pclosed) { pyopen = 1; pyparen = 1 }
      continue
    }
    if (i == nsemi && seg ~ /^[ \t]*from[ \t].*import[ \t]+[^\\]*\\[ \t]*$/) {
      pybase = seg
      sub(/^[ \t]*from[ \t]+/, "", pybase)
      names = pybase
      sub(/[ \t].*$/, "", pybase)
      pymto = ""; pymconf = ""
      if (pybase != "") { resolve(pfrom, plang, pybase, "from-import", plno); pymto = bindto; pymconf = bindconf }
      pyline = stmtline
      sub(/^[^ \t]*[ \t]+import[ \t]+/, "", names)
      sub(/\\[ \t]*$/, "", names)
      py_submodule_names(pfrom, plno, pyline, pybase, pymto, pymconf, names)
      pyopen = 1; pyparen = 0; pyplain = 0
      continue
    }
    # A plain `import a, b, \` continuation: no `from` base, each name
    # resolves as its own import, same as py_plain_names() does inline.
    if (i == nsemi && seg ~ /^[ \t]*import[ \t]+[^\\]*\\[ \t]*$/) {
      names = seg
      sub(/^[ \t]*import[ \t]+/, "", names)
      sub(/\\[ \t]*$/, "", names)
      pyline = stmtline
      py_plain_names(pfrom, plno, pyline, names)
      pyopen = 1; pyparen = 0; pyplain = 1
      continue
    }
    py_stmt(pfrom, seg, plno, stmtline)
  }
}

function scan(from,   lang, line, lno, full, code, m, pend, pendmask, i) {
  lang = lang_of(extof(from))
  if (lang == "") return
  full = (from ~ /^\//) ? from : root "/" from

  # Slurp the file into FL[] (global, capped at 4000 lines - a generated
  # bundle has nothing to say) up front, BOM/CR-stripped exactly as a
  # line-at-a-time read would, so the main loop below can index by physical
  # line number and js_peek_chain() (G1) can look at a LATER line without
  # racing a second read stream against this one.
  nlines = 0
  while ((getline line < full) > 0) {
    nlines++
    if (nlines == 1) sub(/^\357\273\277/, "", line)   # UTF-8 BOM
    sub(/\r$/, "", line)                                # a file saved on Windows
    FL[nlines] = line
    if (nlines >= 4000) break
  }
  close(full)

  blockstate = 0; blockq = ""; ingo = 0; prevjvm = ""; pyopen = ""; pyplain = 0; pcount = 0
  pyopenq = ""
  pend = ""
  for (lno = 1; lno <= nlines; lno++) {
    line = FL[lno]
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

    # decomment() carries no memory across lines of a plain single/double-
    # quoted Python string continued with a trailing "\" (F3): starting
    # fresh here, it reads the string's leftover text as code and misreads
    # its real closing quote as if it OPENED a new string. `pyopenq` is that
    # missing memory - the quote character left open at the end of the
    # PREVIOUS python line, or "" - and this puts the current line right
    # before anything else (including the blank-line check) sees it: the
    # true string body up to its real closing quote is blanked out (the
    # same convention decomment() itself uses for a comment - text that
    # cannot fool a later regex into reading it as a statement) and
    # remasked as string, and only what follows is asked of decomment()
    # again, fresh, for an accurate read of the real code that follows it.
    if (lang == "py" && pyopenq != "") {
      p = py_find_close(code, pyopenq)
      if (p > 0) {
        suffixcode = decomment(substr(code, p + 1), lang)
        suffixmask = strmask
        pyopenq = (length(suffixmask) > length(suffixcode)) ? py_open_quote(suffixcode) : ""
        strmask = repeat_char(p - 1, "S") "." suffixmask
        code = repeat_char(p - 1, " ") substr(code, p, 1) suffixcode
      } else {
        # The string runs past this whole line too - none of it is real
        # code, and `pyopenq` stays open for the next line.
        code = ""; strmask = ""
      }
    } else if (lang == "py") {
      pyopenq = (length(strmask) > length(code)) ? py_open_quote(code) : ""
    }

    if (code ~ /^[ \t]*$/) {
      # A Python backslash continuation joins exactly the next physical
      # line; when that line is comment-only (or blank), it contributes
      # nothing and the logical line ends right there - the statement after
      # it is its own, not more of the continuation's name list (R4b). A
      # parenthesised continuation is unaffected: a blank/comment line
      # inside `( ... )` is ordinary Python and stays open.
      if (lang == "py" && pyopen != "" && !pyparen) pyopen = ""
      continue
    }
    rawcode = code

    # An import statement split across lines: join until the specifier lands.
    # `stmtline` is the line bindings.tsv reports for whatever statement is
    # current: the line this join STARTED on, remembered across every line it
    # takes to land, never the line it happens to finish on. pline[]/plen[]
    # remember where each joined-in physical line begins and how long its own
    # (pre-join) code was, so js_lineof() can map a position back to ITS
    # physical line - not every position in a joined buffer is on the line
    # the join started on: see js_lineof()'s own comment for why that matters.
    # `pendmask` is `pend`'s own strmask, carried along unchanged - a plain
    # dot-fill here (R1) would flatten a joined-in string body to "code",
    # letting a require()/import() written inside it (`a = "require(./evil)"`)
    # match for real once a later line's `}` completes the statement.
    # It is truncated to `code`'s own length at every site that stores it
    # (F2): decomment() itself can grow strmask one character LONGER than
    # its returned code for one line (a trailing "\" inside a string, common
    # to a Python triple-quoted or backslash-continued string, appends "SS"
    # to the mask but only the "\" itself to the text), and an untruncated
    # pendmask then shifts every later in_string() position on the joined
    # buffer by one.
    joined = 0
    if (pend != "") {
      strmask = pendmask "." strmask
      code = pend " " code
      pend = ""
      joined = 1
    }
    if (!joined) { stmtline = lno; pcount = 0 }
    pcount++; pline[pcount] = lno; plen[pcount] = length(rawcode)

    if (lang == "js") {
      if (code ~ /^[ \t]*(import|export)[ \t]/ && code !~ /['"]/ && code !~ /;[ \t]*$/) { pend = code; pendmask = substr(strmask, 1, length(code)); continue }
      # `await import(` with the specifier on the following line.
      if (code ~ /import[ \t]*\([ \t]*$/) { pend = code; pendmask = substr(strmask, 1, length(code)); continue }
      # `const {` / `let {` / `var {` (optionally `export`-prefixed) whose
      # brace does not close on this line: could be a destructured
      # require()/import() a few lines down - js_bind_call() finds it there
      # once the buffer holds the whole declaration. Harmless to join even
      # when it turns out to be an ordinary destructure with no import in it.
      if (code ~ /^[ \t]*(export[ \t]+)?(const|let|var)[ \t]*\{[^{}]*$/) { pend = code; pendmask = substr(strmask, 1, length(code)); continue }
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
        matchend = callpos + RLENGTH - 1
        off += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
        if (quoted) continue
        chained = js_call_chained(rest, lno, lang)
        sub(/^[^'"]*['"]/, "", m); sub(/['"]$/, "", m)
        # The imports.tsv edge's line is the physical line holding the END of
        # THIS call's own match - its closing quote (R2) - not raw `lno`: a
        # `const {\n a,\n b = require(...),\n} = obj` destructure joins
        # several MORE lines into the buffer after this call's own text
        # already landed (see the "const {" join in the main loop), so by
        # the time this runs `lno` is the destructure's CLOSING line, not the
        # call's. js_lineof(matchend), not js_lineof(callpos): a call whose
        # own text spans lines (`await import(\nspec\n)`) must keep reporting
        # where its specifier landed, matching every pre-existing form.
        resolve(from, lang, m, "require", js_lineof(matchend))
        # js_decl_head() (item 9): a LATER declarator of the same
        # `const a = ..., cfg = require(...)` statement has no keyword
        # directly before it - read `head` back only to its own nearest
        # top-level comma so js_bind_call() still recognises it as bound.
        js_bind_call(from, js_lineof(callpos), js_decl_head(head), "cjs", m, chained)
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
        matchend = callpos + RLENGTH - 1
        off += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
        if (quoted) continue
        chained = js_call_chained(rest, lno, lang)
        sub(/^[^'"]*['"]/, "", m); sub(/['"]$/, "", m)
        resolve(from, lang, m, "dynamic-import", js_lineof(matchend))   # R2, see the require() case above
        js_bind_call(from, js_lineof(callpos), js_decl_head(head), "dynamic", m, chained)   # item 9, see the require() case above
      }
      continue
    }

    if (lang == "py") {
      # A parenthesised or backslash-continued from-import (or a plain,
      # backslash-continued `import`): the names are on the lines after the
      # opener, and for the parenthesised form the opener line may name some
      # of them itself (only a bare `from M import (` with nothing after the
      # "(" names none). pyparen tells the parenthesised and backslash
      # continuations apart, since they close on different conditions;
      # pyplain tells a plain `import a, \` continuation from a `from`
      # one, since a plain one resolves each name on its own, not as a
      # submodule of some remembered base.
      if (pyopen != "") {
        t = code
        ended = 0; semipos = 0
        if (pyparen) {
          if (t ~ /\)/) {
            # Whatever follows the closing ")" is not part of THIS list -
            # re-dispatch it as fresh statement(s) of its own (F4):
            # `from app import (models,\n    util); import app.reports`
            # still gives app.reports its own row, not a silently dropped
            # tail. Reuses the same "split point, re-dispatch the rest"
            # mechanism as R4a/GAP1 below.
            pyopen = ""; ended = 1
            semipos = index(t, ")")
            t = substr(code, 1, semipos - 1)
          } else {
            # Inside brackets a trailing "\" is just a continuation, never
            # a name of its own (GAP2): `from app import (models, \` binds
            # `models`, not a bogus row whose name is literally "\".
            sub(/\\[ \t]*$/, "", t)
          }
        } else {
          # A ';' outside a string always ends the CURRENT statement - on
          # the continuation's closing line (R4a) or on a line that itself
          # keeps going for a DIFFERENT statement right after the ';'
          # (GAP1): `from app import models, \` + `    util; from
          # app.other import reports, \` + `    d` binds util to app, then
          # opens a FRESH continuation for app.other on that same line.
          semipos = py_unquoted_semi(t)
          if (semipos > 0) {
            pyopen = ""; ended = 1
            t = substr(code, 1, semipos - 1)
          } else if (t !~ /\\[ \t]*$/) {
            pyopen = ""; ended = 1
          } else {
            sub(/\\[ \t]*$/, "", t)
          }
        }
        if (pyplain) py_plain_names(from, lno, pyline, t)
        else py_submodule_names(from, lno, pyline, pybase, pymto, pymconf, t)
        if (ended && semipos > 0) {
          code = substr(code, semipos + 1)
          strmask = substr(strmask, semipos + 1)
          py_dispatch(from, lang, code, lno)
        }
        continue
      }
      py_dispatch(from, lang, code, lno)
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
        pend = code; sub(/[ \t]*$/, "", pend); pendmask = substr(strmask, 1, length(pend)); prevjvm = ""; continue
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
      alias_kind[nalias]  = A[6]
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
