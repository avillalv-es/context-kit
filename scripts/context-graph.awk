# context-graph builder. Reads a manifest of context files on stdin and emits
# graph.json on stdout. POSIX awk, no external runtime.
#
# stdin records:  <kind>\t<relative path>
# -v root=        project root (absolute)
# -v filelist=    file holding every tracked repo path, one per line
# -v events=      file holding the activity ledger (ts,kind,actor,target), optional
# -v actcap=      max file nodes from the activity ledger (default 60)
# -v generated=   ISO-8601 timestamp
#
# What this graphs is the CONTEXT LAYOUT, not the code. Code structure is in
# the code and an agent can read it; what an agent cannot read is which rule
# will never fire, which knowledge nothing routes to, and which skill has
# never once been used. Those are properties of the layout, and they are only
# visible as a graph.
#
# The node/edge shape and the confidence tag on every edge are adapted from
# graphify (Apache-2.0, Graphify Labs). See NOTICE.

function jesc(s,   out) {
  out = s
  gsub(/\\/, "\\\\", out)
  gsub(/"/, "\\\"", out)
  gsub(/\t/, " ", out)
  gsub(/\r/, "", out)
  gsub(/\n/, " ", out)
  return out
}

function addnode(id, label, kind, path, tier,   i) {
  if (id in nodeidx) return nodeidx[id]
  ncount++
  nodeidx[id] = ncount
  nid[ncount] = id
  nlabel[ncount] = label
  nkind[ncount] = kind
  npath[ncount] = path
  ntier[ncount] = tier
  nlines[ncount] = 0
  nbytes[ncount] = 0
  nissue[ncount] = ""
  ndeg[ncount] = 0
  return ncount
}

function addissue(id, text,   i) {
  if (!(id in nodeidx)) return
  i = nodeidx[id]
  nissue[i] = (nissue[i] == "" ? text : nissue[i] "; " text)
  issues[++icount] = id "\t" text
}

function addedge(src, dst, rel, conf,   key) {
  if (!(src in nodeidx) || !(dst in nodeidx)) return
  key = src "\x01" dst "\x01" rel
  if (key in edgeseen) { edgeweight[key]++; return }
  edgeseen[key] = 1
  edgeweight[key] = 1
  ecount++
  esrc[ecount] = src
  edst[ecount] = dst
  erel[ecount] = rel
  econf[ecount] = conf
  ekey[ecount] = key
  ndeg[nodeidx[src]]++
  ndeg[nodeidx[dst]]++
}

# Resolves a reference written in file `src` to a real path: project-root
# first (the common case in a CLAUDE.md routing table), falling back to
# directory-relative to the file that names it. Returns "" for plain text
# with no repo-relative meaning.
function resolve_candidate(src, t,   cand, d) {
  sub(/^\.\//, "", t)
  cand = t
  if (!(cand in bypath) && !(cand in isrepofile)) {
    d = npath[nodeidx[src]]
    sub(/[^\/]*$/, "", d)
    cand = d t
    while (sub(/[^\/]*\/\.\.\//, "", cand)) { }
    sub(/^\.\//, "", cand)
  }
  return cand
}

function stem(p,   b) { b = basename(p); sub(/\.[^.]*$/, "", b); return b }

# Pull frontmatter and body facts out of a context file in one pass.
# Sets: fm_desc, fm_paths (newline-joined), body_links (newline-joined),
#       body_refs (newline-joined), body_lines (non-blank, non-comment),
#       body_bytes, fm_outcome.
#
# body_refs holds the names a file says out loud - `lean-review`, /context-init
# - as distinct from body_links, which holds paths it links to. A command file
# that says "use the `lean-review` skill" carries no link at all, and that
# sentence IS the wiring, so matching on prose would be the only way to see it.
# Matching on backticks and slash-commands rather than bare words keeps it from
# firing on every English word that happens to be a skill name.
function scanfile(path,   line, tmp, v, full) {
  fm_desc = ""; fm_paths = ""; body_links = ""; body_refs = ""
  body_lines = 0; body_bytes = 0
  fm_outcome = ""; fm_name = ""
  full = (path ~ /^\//) ? path : root "/" path
  infm = 0; fmdone = 0; inlist = 0; listkey = ""
  while ((getline line < full) > 0) {
    body_bytes += length(line) + 1
    if (fm_line(line)) continue
    if (line ~ /^[ \t]*$/) continue
    if (line ~ /^[ \t]*<!--/) continue
    body_lines++
    # Markdown links and @-references to other files in the layout.
    tmp = line
    while (match(tmp, /\]\([^)]+\)/)) {
      v = substr(tmp, RSTART + 2, RLENGTH - 3)
      tmp = substr(tmp, RSTART + RLENGTH)
      sub(/#.*$/, "", v)
      if (v != "" && v !~ /^[a-z]+:\/\//) body_links = body_links v "\n"
    }
    tmp = line
    while (match(tmp, /@[A-Za-z0-9_.\/-]+\.md/)) {
      v = substr(tmp, RSTART + 1, RLENGTH - 1)
      tmp = substr(tmp, RSTART + RLENGTH)
      body_links = body_links v "\n"
    }
    tmp = line
    # The leading character used to be restricted to [A-Za-z0-9], which
    # can never match a dotfile path - and every rule, skill, command and
    # agent in this whole system lives under .claude/. A CLAUDE.md routing
    # table almost always writes `.claude/rules/10-api.md`, not a markdown
    # link, so that restriction meant the single most common reference in
    # this ecosystem was silently uncaptured. Widened to allow a leading
    # `.` or `/` too, matching the @-reference pattern above.
    while (match(tmp, /`[A-Za-z0-9._\/][A-Za-z0-9_.\/-]*`/)) {
      v = substr(tmp, RSTART + 1, RLENGTH - 2)
      tmp = substr(tmp, RSTART + RLENGTH)
      body_refs = body_refs v "\n"
    }
    tmp = line
    while (match(tmp, /\/[a-z][a-z0-9-]+/)) {
      v = substr(tmp, RSTART + 1, RLENGTH - 1)
      tmp = substr(tmp, RSTART + RLENGTH)
      body_refs = body_refs v "\n"
    }
  }
  close(full)
}

BEGIN {
  FS = "\t"
  ncount = 0; ecount = 0; icount = 0; nfiles = 0
  # Repo file list, for resolving a rule's paths: globs against reality.
  if (filelist != "") {
    while ((getline line < filelist) > 0) {
      if (line == "") continue
      nfiles++
      repofile[nfiles] = line
      isrepofile[line] = 1
    }
    close(filelist)
  }
}

# --- manifest ---------------------------------------------------------------
{
  kind = $1
  path = $2
  if (path == "") next
  id = ""
  body_links = ""; body_refs = ""

  if (kind == "tier1") {
    id = "tier1:" path
    i = addnode(id, path, "tier1", path, 1)
    scanfile(path)
    nlines[i] = body_lines
    nbytes[i] = body_bytes
    linksrc[id] = body_links
    root_id = id
  } else if (kind == "rule") {
    id = "rule:" stem(path)
    i = addnode(id, stem(path), "rule", path, 2)
    scanfile(path)
    nlines[i] = body_lines
    nbytes[i] = body_bytes
    ndesc[i] = fm_desc
    rulepaths[id] = fm_paths
    linksrc[id] = body_links
  } else if (kind == "knowledge") {
    id = "knowledge:" stem(path)
    i = addnode(id, stem(path), "knowledge", path, 3)
    scanfile(path)
    nlines[i] = body_lines
    nbytes[i] = body_bytes
    linksrc[id] = body_links
  } else if (kind == "skill") {
    nm = path
    sub(/\/SKILL\.md$/, "", nm)
    nm = basename(nm)
    id = "skill:" nm
    i = addnode(id, nm, "skill", path, 3)
    scanfile(path)
    nlines[i] = body_lines
    nbytes[i] = body_bytes
    ndesc[i] = fm_desc
    linksrc[id] = body_links
    skillname[nm] = id
  } else if (kind == "command") {
    nm = stem(path)
    id = "command:" nm
    i = addnode(id, "/" nm, "command", path, 3)
    scanfile(path)
    nlines[i] = body_lines
    ndesc[i] = fm_desc
    linksrc[id] = body_links
    commandname[nm] = id
  } else if (kind == "agent") {
    nm = stem(path)
    id = "agent:" nm
    i = addnode(id, nm, "agent", path, 3)
    scanfile(path)
    nlines[i] = body_lines
    ndesc[i] = fm_desc
    linksrc[id] = body_links
  } else if (kind == "finding") {
    nm = stem(path)
    id = "finding:" nm
    i = addnode(id, nm, "finding", path, 3)
    scanfile(path)
    nlines[i] = body_lines
    linksrc[id] = body_links
  } else if (kind == "doc") {
    # A link source, not a tier. It gets a node so its links have somewhere
    # to start from, and it is never itself flagged for being unreachable.
    id = "doc:" path
    i = addnode(id, basename(path), "doc", path, 0)
    scanfile(path)
    nlines[i] = body_lines
  } else if (kind == "hook") {
    id = "hook:" basename(path)
    addnode(id, basename(path), "hook", path, 0)
  }
  if (id != "") {
    linksrc[id] = body_links
    refsrc[id] = body_refs
    bypath[path] = id
  }
}

END {
  # --- routes_to: an explicit link from one context file to another ---------
  for (src in linksrc) {
    n = split(linksrc[src], L, "\n")
    for (j = 1; j <= n; j++) {
      t = L[j]
      if (t == "") continue
      cand = resolve_candidate(src, t)
      if (cand in bypath) {
        if (bypath[cand] != src) addedge(src, bypath[cand], "routes_to", "EXTRACTED")
      } else if (cand in isrepofile) {
        # A link out of the layout into an ordinary repo file - a rule citing
        # the doc that is its authority, say. Worth a node: it shows which
        # decisions a rule rests on, and which docs nothing rests on.
        did = "doc:" cand
        addnode(did, basename(cand), "doc", cand, 0)
        addedge(src, did, "cites", "EXTRACTED")
      }
    }
  }

  # --- covers: a tier-2 rule's paths: globs, matched against the real tree --
  for (rid in rulepaths) {
    n = split(rulepaths[rid], P, "\n")
    total = 0
    declared = 0
    catchall = 0
    for (j = 1; j <= n; j++) {
      g = P[j]
      if (g == "") continue
      declared++
      if (g == "**" || g == "**/*" || g == "*" || g == "**/**") catchall = 1
      re = globre(g)
      hits = 0
      for (k = 1; k <= nfiles; k++) if (repofile[k] ~ re) { hits++; covered[repofile[k]] = 1 }
      gid = "path:" g
      addnode(gid, g, "path", "", 2)
      pathhits[gid] = hits
      addedge(rid, gid, "covers", "EXTRACTED")
      total += hits
    }
    rulereach[rid] = total
    if (declared == 0) {
      addissue(rid, "no paths: frontmatter - loads on every session, so this is tier 1 without tier 1's scrutiny")
    } else if (catchall) {
      addissue(rid, "paths: matches the whole tree - this is tier 1 wearing a tier-2 costume")
    } else if (total == 0) {
      addissue(rid, "paths: match no file in this repo - this rule can never fire")
    }
  }

  # --- mentions: a file names a skill or command out loud -------------------
  # Exact line match against the collected references, never a substring:
  # `lean-review` must not also count as a mention of `lean`.
  #
  # A backtick span and a bare `/word` fragment land in the same pool, and
  # only the span can ever be a file path - a bare fragment is a slug with no
  # slash, by construction. The routing table a CLAUDE.md actually writes is
  # almost always `` `.claude/rules/10-api.md` ``, not a markdown link, so a
  # candidate that looks path-shaped is also tried against the real paths -
  # same resolution as an explicit link, one rung lower in confidence because
  # a code span is formatting, not syntax that promises a reference.
  for (src in refsrc) {
    n = split(refsrc[src], R, "\n")
    for (j = 1; j <= n; j++) {
      t = R[j]
      if (t == "") continue
      if (t in skillname && skillname[t] != src) {
        addedge(src, skillname[t], "mentions", "INFERRED")
      }
      if (t in commandname && commandname[t] != src) {
        addedge(src, commandname[t], "mentions", "INFERRED")
      }
      if (t ~ /\// || t ~ /\.md$/) {
        cand = resolve_candidate(src, t)
        if (cand in bypath) {
          if (bypath[cand] != src) addedge(src, bypath[cand], "routes_to", "INFERRED")
        } else if (cand in isrepofile) {
          did = "doc:" cand
          addnode(did, basename(cand), "doc", cand, 0)
          addedge(src, did, "cites", "INFERRED")
        }
      }
    }
  }

  # --- activity ledger ------------------------------------------------------
  if (events != "") {
    while ((getline eline < events) > 0) {
      if (eline == "") continue
      split(eline, E, "\t")
      ets = E[1]; ekind = E[2]; eactor = E[3]; etarget = E[4]
      if (eactor == "" || etarget == "") continue
      aid = "session:" eactor
      addnode(aid, eactor, "session", "", 0)
      if (ets > lastseen) lastseen = ets
      if (ekind == "agent") {
        tid = "agent:" etarget
        if (!(tid in nodeidx)) addnode(tid, etarget, "agent", "", 3)
        addedge(aid, tid, "spawned", "OBSERVED")
        agentseen[tid] = 1
      } else if (ekind == "skill") {
        tid = "skill:" etarget
        if (!(tid in nodeidx)) addnode(tid, etarget, "skill", "", 3)
        addedge(aid, tid, "used", "OBSERVED")
        fired[tid] = 1
      } else if (ekind == "read" || ekind == "write") {
        # Deferred: the busiest paths are picked below, once the whole
        # ledger has been counted.
        nact++
        actor_of[nact] = aid; path_of[nact] = etarget; kind_of[nact] = ekind
        touched[etarget] = touched[etarget] + 1
      }
    }
    close(events)

    # Cap the activity layer the way codecap caps the code layer. The hook
    # now records bash reads, so one busy session can name several hundred
    # distinct files; every one of them used to become a node here and the
    # canvas became unreadable. Rank by how often a path was touched and
    # keep the busiest, plus anything in the context manifest, which is
    # never noise. Selection is by touch count, and a whole tier is taken or
    # dropped together rather than split arbitrarily - so the result lands at
    # or below the cap, sometimes well below when counts are chunky (a
    # hundred files touched once each is all-or-nothing).
    if (actcap == "" || actcap + 0 < 1) actcap = 60
    maxc = 0
    for (pth in touched) if (touched[pth] > maxc) maxc = touched[pth]
    thr = 1
    for (t = maxc; t >= 1; t--) {
      c = 0
      for (pth in touched) if (touched[pth] >= t) c++
      if (c > actcap) { thr = t + 1; break }
      thr = t
    }
    for (a = 1; a <= nact; a++) {
      etarget = path_of[a]
      if (!(etarget in bypath) && touched[etarget] < thr) continue
      tid = "file:" etarget
      if (etarget in bypath) tid = bypath[etarget]
      else if (!(tid in nodeidx)) addnode(tid, basename(etarget), "file", etarget, 0)
      addedge(actor_of[a], tid, (kind_of[a] == "write" ? "wrote" : "read"), "OBSERVED")
    }
  }

  # --- code layer -----------------------------------------------------------
  # Only the load-bearing modules. A real app has thousands of source files
  # and drawing them all produces a hairball that answers nothing; what the
  # LAYOUT graph wants to show is which modules everything flows through, so
  # the code layer is capped by fan-in. blast-radius reads the full,
  # uncapped edge list separately - the cap is a display decision, not a
  # data one.
  if (imports != "") {
    while ((getline iline < imports) > 0) {
      if (iline == "") continue
      split(iline, IE, "\t")
      isrc = IE[1]; idst = IE[2]
      if (isrc == "" || idst == "" || isrc == idst) continue
      nimp++
      fanin[idst]++
      fanout[isrc]++
      impsrc[nimp] = isrc; impdst[nimp] = idst; impconf[nimp] = IE[5]
      if (!(isrc in modseen)) { modseen[isrc] = 1; modlist[++nmod] = isrc }
      if (!(idst in modseen)) { modseen[idst] = 1; modlist[++nmod] = idst }
    }
    close(imports)

    if (codecap == "" || codecap + 0 < 1) codecap = 120
    # Rank by total degree, then by path so the selection is stable between
    # runs on an unchanged repo.
    for (i = 1; i <= nmod; i++) {
      m = modlist[i]
      score[m] = fanin[m] + fanout[m]
    }
    nkeep = 0
    for (i = 1; i <= nmod; i++) {
      m = modlist[i]
      # Always keep a module the activity ledger touched or a rule claims -
      # those are the ones the layout has an opinion about.
      if (score[m] >= 1 || (m in touched) || (m in covered)) { keep[++nkeep] = m }
    }
    # Insertion sort by score desc, path asc. nkeep is capped by the repo's
    # module count; this runs once.
    for (i = 2; i <= nkeep; i++) {
      tmpv = keep[i]
      for (j = i - 1; j >= 1; j--) {
        a = keep[j]
        if (score[a] > score[tmpv] || (score[a] == score[tmpv] && a < tmpv)) break
        keep[j + 1] = a
      }
      keep[j + 1] = tmpv
    }
    nshown = (nkeep < codecap) ? nkeep : codecap
    for (i = 1; i <= nshown; i++) {
      m = keep[i]
      mid = "module:" m
      shown[m] = 1
      if (!(mid in nodeidx)) {
        k = addnode(mid, basename(m), "module", m, 0)
        nfanin[k] = fanin[m] + 0
      }
    }
    for (j = 1; j <= nimp; j++) {
      if (!(impsrc[j] in shown) || !(impdst[j] in shown)) continue
      addedge("module:" impsrc[j], "module:" impdst[j], "imports",
              (impconf[j] == "INFERRED") ? "INFERRED" : "EXTRACTED")
    }
    if (nkeep > nshown)
      dropped_modules = nkeep - nshown

    # The cross-layer question, and the only one neither grep nor a code
    # index can answer on its own: which modules is everything leaning on,
    # with no tier-2 rule written for them?
    nhot = 0
    for (i = 1; i <= nshown && i <= 25; i++) {
      m = keep[i]
      if (fanin[m] < 3) continue
      if (m in covered) continue
      addissue("module:" m,
        fanin[m] " files import this and no rule covers it - conventions for a module this load-bearing are worth writing down")
      nhot++
    }
  }

  # --- layout findings ------------------------------------------------------
  for (i = 1; i <= ncount; i++) {
    id = nid[i]
    if (nkind[i] == "knowledge" || nkind[i] == "rule") {
      inbound = 0
      for (j = 1; j <= ecount; j++) {
        if (edst[j] == id && (erel[j] == "routes_to" || erel[j] == "mentions")) inbound++
      }
      if (inbound == 0 && nkind[i] == "knowledge") {
        addissue(id, "nothing routes here - tier 3 is only reachable by lookup, so an unlinked file is invisible")
      }
    }
    if (nkind[i] == "skill" && npath[i] != "") {
      if (!(id in fired) && events != "" && lastseen != "") {
        addissue(id, "never invoked in the recorded activity - check the description is written as a trigger")
      }
      if (ndesc[i] == "") {
        addissue(id, "no description - the description is the entire firing mechanism")
      } else if (ndesc[i] !~ /[Uu]se when|[Uu]se immediately|[Uu]se for/) {
        addissue(id, "description is not written as a trigger (no \"use when\") - it will not fire")
      }
      if (nbytes[i] > 12000) {
        addissue(id, "SKILL.md is " int(nbytes[i]/1024) "KB - split the reference material into references/ so only the core loads")
      }
    }
    if (nkind[i] == "tier1" && nlines[i] > 120) {
      addissue(id, nlines[i] " lines in tier 1, paid on every session and every subagent - audit with /context-init")
    }
  }

  # --- emit -----------------------------------------------------------------
  print "{"
  printf "  \"schema\": 1,\n"
  printf "  \"generated\": \"%s\",\n", jesc(generated)
  printf "  \"root\": \"%s\",\n", jesc(root)
  printf "  \"nodes\": [\n"
  for (i = 1; i <= ncount; i++) {
    printf "    {\"id\": \"%s\", \"label\": \"%s\", \"kind\": \"%s\", \"tier\": %d, \"path\": \"%s\", \"lines\": %d, \"bytes\": %d, \"degree\": %d",
      jesc(nid[i]), jesc(nlabel[i]), jesc(nkind[i]), ntier[i], jesc(npath[i]), nlines[i], nbytes[i], ndeg[i]
    if (nkind[i] == "path") printf ", \"matches\": %d", pathhits[nid[i]] + 0
    if (nkind[i] == "module") printf ", \"fanin\": %d", nfanin[i] + 0
    if (ndesc[i] != "") printf ", \"description\": \"%s\"", jesc(ndesc[i])
    if (nissue[i] != "") printf ", \"issue\": \"%s\"", jesc(nissue[i])
    printf "}%s\n", (i < ncount ? "," : "")
  }
  printf "  ],\n"
  printf "  \"edges\": [\n"
  for (j = 1; j <= ecount; j++) {
    printf "    {\"source\": \"%s\", \"target\": \"%s\", \"relation\": \"%s\", \"confidence\": \"%s\", \"weight\": %d}%s\n",
      jesc(esrc[j]), jesc(edst[j]), jesc(erel[j]), jesc(econf[j]), edgeweight[ekey[j]], (j < ecount ? "," : "")
  }
  printf "  ],\n"
  printf "  \"issues\": [\n"
  for (j = 1; j <= icount; j++) {
    split(issues[j], IS, "\t")
    printf "    {\"node\": \"%s\", \"text\": \"%s\"}%s\n", jesc(IS[1]), jesc(IS[2]), (j < icount ? "," : "")
  }
  printf "  ],\n"
  printf "  \"stats\": {\"nodes\": %d, \"edges\": %d, \"issues\": %d, \"repo_files\": %d, \"tier1_lines\": %d, \"modules\": %d, \"modules_hidden\": %d, \"import_edges\": %d}\n",
    ncount, ecount, icount, nfiles, (root_id != "" ? nlines[nodeidx[root_id]] : 0),
    nshown + 0, dropped_modules + 0, nimp + 0
  print "}"
}
