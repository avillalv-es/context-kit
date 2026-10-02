# Reverse-traverse a file-level import graph and print the blast-radius report.
# POSIX awk: no gawk extensions, so it runs under gawk, mawk and BWK awk.
#
# -v seeds=       seed file, one per line: path<TAB>tag  (the tag is optional)
# -v edges=       import edges: from<TAB>to<TAB>lang<TAB>form<TAB>confidence<TAB>line
# -v unresolved=  dropped imports: from<TAB>module<TAB>reason<TAB>line
# -v hits=        optional, symbol mode: path<TAB>line<TAB>text for each use
# -v notes=       optional file of one-line notes, printed under Seeds
# -v symbol=      optional, the symbol being traced
# -v depth=       hops to walk back (default 3)
# -v max=         rows printed per depth (default 40)
# -v sortfile=    scratch path; every ordered list goes through sort(1) into it
#
# Walks IMPORTERS, not imports: an edge a -> b means "a imports b", so the
# blast radius of b is everything that reaches b by following edges backwards.
# That direction is the whole point - grep finds the name, but only the
# reversed graph answers "what breaks if I change this".
#
# The output is a contract (see docs/blast-radius.md): a stats line, then
# `## ` sections that appear only when they have something to say. Everything
# is ordered by sort(1) under LC_ALL=C, and the walk picks each file's parent
# by a fixed rule rather than by hash order, so two runs print the same bytes.
#
# The reverse-traversal shape (breadth-first from a resolved seed, bounded
# depth, carrying the relation and the edge's own source line so every row has
# somewhere to click) is adapted from graphify's affected.py (Apache-2.0,
# Graphify Labs). See NOTICE.

function basename(p,   b) { b = p; sub(/.*\//, "", b); return b }
function dirname(p,   d)  { d = p; if (d !~ /\//) return ""; sub(/\/[^\/]*$/, "", d); return d }
function stripext(b)      { sub(/\.[^.\/]*$/, "", b); return b }
function lastseg(s)       { sub(/\/+$/, "", s); sub(/.*\//, "", s); return s }

# A file the reader would run: *.test.*, *.spec.*, test_*.py, *_test.py,
# *_test.go, *Test(s).cs, *Test(s).java, *_spec.rb, or anything under a tests/,
# test/, __tests__/ or spec/ directory.
function is_test(p,   b) {
  b = basename(p)
  if (p ~ /(^|\/)(tests|test|__tests__|spec)\//) return 1
  if (b ~ /\.(test|spec)\./) return 1
  if (b ~ /^test_.*\.py$/ || b ~ /_test\.py$/) return 1
  if (b ~ /_test\.go$/) return 1
  if (b ~ /Tests?\.(cs|java)$/) return 1
  if (b ~ /_spec\.rb$/) return 1
  return 0
}

# Reasons an import is expected not to resolve: a package from outside the
# repo, the standard library, a system header. Counting them as blind spots
# buries the few that are real.
function expected_external(r) {
  return (r == "external-package" || r == "stdlib" || r == "external-or-stdlib" || \
          r == "external-or-jdk" || r == "external-crate" || r == "system-header" || \
          r == "trait-use-not-an-import")
}

# Does an unresolved import name one of the seeds? It matches on the last path
# segment (or its dotted tail) against the seed's file stem, which is how a
# Vue `@/lib/auth` that no alias resolved still points at src/lib/auth.ts.
function stem_match(spec, reason,   s1, s2, s3) {
  if (expected_external(reason) && spec !~ /[\/.]/) return ""
  s1 = lastseg(spec)
  if (s1 == "") return ""
  if (s1 in stemseed) return stemseed[s1]
  s2 = s1
  if (s2 ~ /\.(js|jsx|mjs|cjs|ts|tsx|mts|cts|vue|svelte|astro|py|go|java|kt|cs|rs|rb|php|json)$/) {
    sub(/\.[^.]*$/, "", s2)
    if (s2 in stemseed) return stemseed[s2]
  }
  if (spec !~ /\//) {
    s3 = s1; sub(/.*\./, "", s3)
    if (s3 != "" && (s3 in stemseed)) return stemseed[s3]
  }
  return ""
}

# Which parent explains a file best? The smallest parent path, then a literal
# edge over an inferred one, then the earliest import line. Any fixed rule
# would do; what matters is that it does not depend on the order edges were read.
function better(t, c, l, ot, oc, ol) {
  if ((t "") != (ot "")) return ((t "") < (ot ""))
  if (c != oc) return (c == "EXTRACTED")
  return ((l + 0) < (ol + 0))
}

BEGIN {
  FS = "\t"
  if (depth == "" || depth + 0 < 1) depth = 3
  if (max == "" || max + 0 < 1) max = 40
  depth += 0; max += 0

  # --- read the seeds ---------------------------------------------------------
  nseed = 0
  while ((getline line < seeds) > 0) {
    if (line == "") continue
    p = line; tag = ""
    t = index(line, "\t")
    if (t > 0) { p = substr(line, 1, t - 1); tag = substr(line, t + 1) }
    if (p == "" || (p in isseed)) continue
    isseed[p] = 1
    seedtag[p] = tag
    seedgone[p] = (tag ~ /^(deleted|renamed to)/) ? 1 : 0
    nseed++
    seedlist[nseed] = p
  }
  close(seeds)
  if (nseed == 0) {
    print "blast-radius: no seed files - nothing to trace" > "/dev/stderr"
    exit 3
  }

  # --- reverse adjacency: for each target, the files that import it -----------
  nedge = 0
  while ((getline line < edges) > 0) {
    if (line == "") continue
    n = split(line, E, "\t")
    if (n < 2) continue
    src = E[1]; dst = E[2]
    if (src == "" || dst == "" || src == dst) continue
    nedge++
    k = ++rn[dst]
    rev[dst, k] = src
    revform[dst, k] = E[4]
    revconf[dst, k] = E[5]
    revline[dst, k] = E[6]
    seenfile[src] = 1
    seenfile[dst] = 1
  }
  close(edges)

  # --- symbol uses ------------------------------------------------------------
  anyhit = 0
  if (hits != "") {
    while ((getline line < hits) > 0) {
      if (line == "") continue
      p1 = index(line, "\t")
      if (p1 == 0) continue
      f = substr(line, 1, p1 - 1)
      rest = substr(line, p1 + 1)
      p2 = index(rest, "\t")
      if (p2 == 0) { ln = rest; tx = "" }
      else { ln = substr(rest, 1, p2 - 1); tx = substr(rest, p2 + 1) }
      sub(/\r$/, "", tx)
      nh = ++hitn[f]
      hitline[f, nh] = ln
      hittext[f, nh] = tx
      anyhit = 1
    }
    close(hits)
  }

  # --- breadth-first walk backwards -------------------------------------------
  for (i = 1; i <= nseed; i++) frontier[i] = seedlist[i]
  nfront = nseed
  total = 0
  maxd = 0

  for (d = 1; d <= depth; d++) {
    ncand = 0
    for (i = 1; i <= nfront; i++) {
      t = frontier[i]
      for (k = 1; k <= rn[t]; k++) {
        s = rev[t, k]
        if (s in reached || s in isseed) continue
        if (!(s in cand)) {
          cand[s] = 1
          cl[++ncand] = s
          take = 1
        } else {
          take = better(t, revconf[t, k], revline[t, k], cvia[s], cconf[s], cline[s])
        }
        if (take) {
          cvia[s] = t; cconf[s] = revconf[t, k]; cline[s] = revline[t, k]
        }
      }
    }
    if (ncand == 0) break
    for (j = 1; j <= ncand; j++) {
      s = cl[j]
      reached[s] = d
      via[s] = cvia[s]; viaconf[s] = cconf[s]; vialine[s] = cline[s]
      frontier[j] = s
      delete cand[s]
    }
    nfront = ncand
    total += ncand
    maxd = d
  }

  # --- what the seeds look like, for the blind-spot scan ----------------------
  for (i = 1; i <= nseed; i++) {
    p = seedlist[i]
    seeddir[dirname(p)] = 1
    b = stripext(basename(p))
    if (b == "index" || b == "__init__" || b == "mod") b = basename(dirname(p))
    if (b != "" && !(b in stemseed)) stemseed[b] = p
  }

  # --- blind spots ------------------------------------------------------------
  # Only imports that could have hidden an importer: not packages, not the
  # standard library. Counted next to the seeds, plus any unresolved import
  # anywhere whose name matches a seed.
  ngap = 0; nnear = 0; nmissed = 0
  if (unresolved != "") {
    while ((getline line < unresolved) > 0) {
      if (line == "") continue
      split(line, U, "\t")
      from = U[1]; spec = U[2]; reason = U[3]; lno = U[4]
      if (reason == "") reason = "unresolved"
      if (from in isseed || from in reached) continue
      near = (!expected_external(reason) && (dirname(from) in seeddir)) ? 1 : 0
      m = stem_match(spec, reason)
      if (near) { nnear++; bycount[reason]++ }
      if (m != "") {
        nmissed++
        q[++nq] = sprintf("5 %s\t%07d\t%s\t%s\t%s", from, lno + 0, spec, reason, m)
      }
      if (near || m != "") ngap++
    }
    close(unresolved)
  }

  # --- gather every ordered list and sort it once -----------------------------
  ns = 0
  for (f in reached) {
    S[++ns] = sprintf("1%03d %s", reached[f], f)
    if (is_test(f)) tests[f] = 1
  }
  if (anyhit) {
    for (f in hitn) {
      if (f in reached || f in isseed) continue
      S[++ns] = "2 " f
      if (is_test(f)) tests[f] = 1
    }
  }
  for (i = 1; i <= nseed; i++) {
    p = seedlist[i]
    if (!seedgone[p] && is_test(p)) tests[p] = 1
  }

  for (f in tests) S[++ns] = "3 " f
  for (r in bycount) S[++ns] = "4 " r
  for (i = 1; i <= nq; i++) S[++ns] = q[i]

  nr = 0; nn = 0; nt = 0; nb = 0; ng = 0
  if (ns > 0) {
    cmd = "LC_ALL=C sort > '" sortfile "'"
    for (i = 1; i <= ns; i++) print S[i] | cmd
    close(cmd)
    while ((getline line < sortfile) > 0) {
      kind = substr(line, 1, 1)
      if (kind == "1") {
        dd = substr(line, 2, 3) + 0
        RN[dd]++
        R[dd, RN[dd]] = substr(line, 6)
      } else if (kind == "2") N2[++nn] = substr(line, 3)
      else if (kind == "3") T3[++nt] = substr(line, 3)
      else if (kind == "4") B4[++nb] = substr(line, 3)
      else if (kind == "5") G5[++ng] = substr(line, 3)
    }
    close(sortfile)
  }

  # --- the report -------------------------------------------------------------
  printf "blast-radius: seeds=%d affected=%d depth=%d edges=%d gaps=%d\n", nseed, total, maxd, nedge, ngap

  printf "\n## Seeds\n"
  for (i = 1; i <= nseed && i <= max; i++) {
    p = seedlist[i]
    printf "%s", p
    if (seedtag[p] != "") printf "   [%s]", seedtag[p]
    if (!(p in seenfile)) printf "   [no resolved imports touch this file]"
    printf "\n"
  }
  if (nseed > max) printf "... and %d more seeds\n", nseed - max
  if (notes != "") {
    while ((getline line < notes) > 0) if (line != "") printf "note: %s\n", line
    close(notes)
  }
  if (total == 0) {
    print "note: Nothing imports the seed file(s) through a resolved import. That is a"
    print "  leaf (an entry point, a script, a test), a module reached only at runtime"
    print "  (route table, DI container, plugin registry), or an import form that did"
    print "  not resolve - see Blind spots, and grep for the name."
  }
  printf "\n"

  for (d = 1; d <= maxd; d++) {
    if (RN[d] == 0) continue
    printf "## Depth %d\n", d
    shown = 0
    for (j = 1; j <= RN[d] && shown < max; j++) {
      shown++
      f = R[d, j]
      loc = (vialine[f] != "" && vialine[f] + 0 > 0) ? (f ":" vialine[f]) : f
      printf "%s -> %s", loc, via[f]
      if (viaconf[f] == "INFERRED") printf "   [inferred import, verify]"
      printf "\n"
      if (anyhit && (f in hitn)) {
        for (k = 1; k <= hitn[f] && k <= 3; k++)
          printf "  %s:%s  %s\n", f, hitline[f, k], substr(hittext[f, k], 1, 90)
        if (hitn[f] > 3) printf "  ... %d more uses of `%s` in this file\n", hitn[f] - 3, symbol
      }
    }
    if (RN[d] > shown) printf "... and %d more at this depth (raise --max)\n", RN[d] - shown
    printf "\n"
  }

  if (nn > 0) {
    printf "## Name matches\n"
    printf "`%s` appears here with no import path to a seed: usually a different symbol with the same name. Read before believing.\n", symbol
    cap = (max < 15) ? max : 15
    for (j = 1; j <= nn && j <= cap; j++) {
      f = N2[j]
      printf "%s:%s  %s\n", f, hitline[f, 1], substr(hittext[f, 1], 1, 80)
    }
    if (nn > cap) printf "... and %d more\n", nn - cap
    printf "\n"
  }

  if (nt > 0) {
    printf "## Tests to run\n"
    for (j = 1; j <= nt && j <= max; j++) printf "%s\n", T3[j]
    if (nt > max) printf "... and %d more (raise --max)\n", nt - max
    printf "\n"
  }

  if (ngap > 0) {
    printf "## Blind spots\n"
    if (nnear > 0) {
      printf "%d unresolved import%s next to the seeds; what they point at is unknown:\n", nnear, (nnear == 1 ? "" : "s")
      for (j = 1; j <= nb; j++) printf "  %-26s %d\n", B4[j], bycount[B4[j]]
    }
    if (nmissed > 0) {
      printf "Possible missed importers - an unresolved import whose name matches a seed, verify:\n"
      for (j = 1; j <= ng && j <= max; j++) {
        split(G5[j], Gf, "\t")
        printf "  %s:%d  \"%s\"  [%s]  ~ %s\n", Gf[1], Gf[2] + 0, Gf[3], Gf[4], Gf[5]
      }
      if (ng > max) printf "  ... and %d more\n", ng - max
    }
    printf "\n"
  }

  # Unconditional. The limitation is a property of a file-level import graph,
  # not of how many imports happened to resolve in this repo, and a clean
  # resolution run is exactly when a reader is most likely to mistake this
  # for a complete answer.
  print "This follows imports between files. It cannot see runtime wiring -"
  print "route tables, dependency injection, plugin registries, reflection,"
  print "string-keyed factories - and it does not track which function calls"
  print "which. Treat it as a strong starting set, never as a complete one."
}
