# Reverse-traverse a file-level import graph. POSIX awk.
#
# -v seeds=      file of seed paths, one per line
# -v depth=      how many hops to walk back (default 3)
# -v edges=      the import edge list: from<TAB>to<TAB>lang<TAB>form<TAB>confidence<TAB>line
# -v symbol=     optional: the symbol being changed, for the grep overlay
# -v hits=       optional: file of "path<TAB>line<TAB>text" where the symbol appears
# -v unresolved= optional: the dropped-import list, so the report can admit its blind spots
# -v max=        cap on rows printed per depth (default 40)
#
# Walks IMPORTERS, not imports: an edge a -> b means "a imports b", so the
# blast radius of b is everything that reaches b by following edges backwards.
# That direction is the whole point - grep finds the name, but only the
# reversed graph answers "what breaks if I change this".
#
# The reverse-traversal shape (breadth-first from a resolved seed, bounded
# depth, carrying the relation and the edge's own source line so every row has
# somewhere to click) is adapted from graphify's affected.py (Apache-2.0,
# Graphify Labs). See NOTICE.

BEGIN {
  FS = "\t"
  if (depth == "" || depth + 0 < 1) depth = 3
  if (max == "" || max + 0 < 1) max = 40

  nseed = 0
  while ((getline line < seeds) > 0) {
    if (line == "") continue
    if (line in isseed) continue
    isseed[line] = 1
    nseed++
    seedlist[nseed] = line
  }
  close(seeds)
  if (nseed == 0) {
    print "blast-radius: no seed files - nothing to trace" > "/dev/stderr"
    exit 3
  }

  # Reverse adjacency: for each target, the files that import it.
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

  if (hits != "") {
    while ((getline line < hits) > 0) {
      if (line == "") continue
      split(line, H, "\t")
      if (H[1] == "") continue
      nh = ++hitn[H[1]]
      hitline[H[1], nh] = H[2]
      hittext[H[1], nh] = H[3]
      anyhit = 1
    }
    close(hits)
  }

  nunres = 0
  if (unresolved != "") {
    while ((getline line < unresolved) > 0) {
      if (line == "") continue
      split(line, U, "\t")
      nunres++
      if (U[1] in isseed || U[1] in reached) unres_near[U[1]] = unres_near[U[1]] " " U[2]
      byreason[U[3] == "" ? "unresolved" : U[3]]++
    }
    close(unresolved)
  }

  # --- breadth-first walk backwards ---------------------------------------
  for (i = 1; i <= nseed; i++) { reached[seedlist[i]] = 0; frontier[i] = seedlist[i] }
  nfront = nseed
  total = 0

  for (d = 1; d <= depth; d++) {
    nnext = 0
    for (i = 1; i <= nfront; i++) {
      t = frontier[i]
      for (k = 1; k <= rn[t]; k++) {
        s = rev[t, k]
        if (s in reached || s in isseed) continue
        reached[s] = d
        via[s] = t
        viaform[s] = revform[t, k]
        viaconf[s] = revconf[t, k]
        vialine[s] = revline[t, k]
        total++
        nnext++
        nextf[nnext] = s
        ndepth[d]++
        atdepth[d, ndepth[d]] = s
      }
    }
    if (nnext == 0) break
    for (i = 1; i <= nnext; i++) frontier[i] = nextf[i]
    nfront = nnext
  }

  # --- report -------------------------------------------------------------
  printf "Blast radius"
  if (symbol != "") printf " of `%s`", symbol
  printf "\n\n"

  printf "Seed%s (%d):\n", (nseed == 1 ? "" : "s"), nseed
  for (i = 1; i <= nseed && i <= 20; i++) {
    printf "  %s%s\n", seedlist[i], ((seedlist[i] in seenfile) ? "" : "   [no resolved imports touch this file]")
  }
  if (nseed > 20) printf "  ... and %d more\n", nseed - 20
  printf "\n"

  if (total == 0) {
    print "Nothing imports the seed file(s) through a resolved import."
    print ""
    print "That means one of three things, and they are not the same:"
    print "  - it really is a leaf (an entry point, a script, a test)"
    print "  - it is reached dynamically - a route table, a DI container, a"
    print "    plugin registry, a string-keyed factory - which a file-level"
    print "    import graph cannot see"
    print "  - its importers use an import form that did not resolve (see below)"
    print ""
  } else {
    printf "%d file%s downstream, to depth %d:\n\n", total, (total == 1 ? "" : "s"), depth
    for (d = 1; d <= depth; d++) {
      if (ndepth[d] == 0) continue
      printf "  depth %d - %s (%d)\n", d,
        (d == 1 ? "imports a seed directly" : "imports something at depth " (d - 1)), ndepth[d]
      shown = 0
      for (i = 1; i <= ndepth[d]; i++) {
        f = atdepth[d, i]
        if (shown >= max) break
        shown++
        loc = (vialine[f] != "" && vialine[f] + 0 > 0) ? (f ":" vialine[f]) : f
        printf "    %-52s -> %s", loc, via[f]
        if (viaconf[f] == "INFERRED") printf "   [inferred import, verify]"
        printf "\n"
        if (anyhit && (f in hitn)) {
          for (k = 1; k <= hitn[f] && k <= 3; k++)
            printf "      %s:%s  %s\n", f, hitline[f, k], substr(hittext[f, k], 1, 90)
          if (hitn[f] > 3) printf "      ... %d more uses of `%s` in this file\n", hitn[f] - 3, symbol
        }
      }
      if (ndepth[d] > shown) printf "    ... and %d more at this depth\n", ndepth[d] - shown
      printf "\n"
    }
  }

  if (anyhit) {
    named = 0
    for (f in hitn) if (!(f in reached) && !(f in isseed)) named++
    if (named > 0) {
      printf "`%s` also appears in %d file%s the import graph does not connect to the seed:\n",
        symbol, named, (named == 1 ? "" : "s")
      shown = 0
      for (f in hitn) {
        if (f in reached || f in isseed) continue
        if (shown >= 15) { printf "  ... and %d more\n", named - shown; break }
        shown++
        printf "  %s:%s  %s\n", f, hitline[f, 1], substr(hittext[f, 1], 1, 80)
      }
      print ""
      print "Those are NAME matches, not resolved dependencies. Same name, unrelated"
      print "symbol, is the common case - read before believing."
      print ""
    }
  }

  if (nunres > 0) {
    printf "Blind spots: %d import%s in this repo did not resolve to a file",
      nunres, (nunres == 1 ? "" : "s")
    printf " and are absent from the walk above.\n"
    for (r in byreason) printf "  %-22s %d\n", r, byreason[r]
    print ""
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
