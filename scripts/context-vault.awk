# graph.json -> an Obsidian vault of wikilinked notes. POSIX awk.
#
# -v vault=    output directory
# -v manifest= ownership manifest path
# -v root=     project root, for the source links
#
# Point --dir at a vault you already use and nothing of yours is touched: the
# manifest records every note this wrote, and a file that exists but is not
# in it belongs to you and is skipped. That rule is graphify's, which learned
# it by clobbering people's notes first (Apache-2.0, Graphify Labs).
#
# The parser is deliberately narrow - it reads the one-object-per-line JSON
# this project's own builder writes, and nothing else. A general JSON parser
# in awk would be a rung-1 answer to a problem nobody has.

function jval(line, key,   re, seg, out, i, c, esc) {
  re = "\"" key "\"[ ]*:[ ]*\""
  if (!match(line, re)) return ""
  seg = substr(line, RSTART + RLENGTH)
  out = ""; esc = 0
  for (i = 1; i <= length(seg); i++) {
    c = substr(seg, i, 1)
    if (esc) {
      if (c == "n") out = out " "
      else if (c == "t") out = out " "
      else out = out c
      esc = 0; continue
    }
    if (c == "\\") { esc = 1; continue }
    if (c == "\"") break
    out = out c
  }
  return out
}

function jnum(line, key,   re) {
  re = "\"" key "\"[ ]*:[ ]*-?[0-9]+"
  if (!match(line, re)) return ""
  return substr(line, RSTART + RLENGTH - length(line) + length(line)) + 0
}

function jint(line, key,   re, seg) {
  re = "\"" key "\"[ ]*:[ ]*"
  if (!match(line, "\"" key "\"[ ]*:[ ]*-?[0-9]+")) return ""
  seg = substr(line, RSTART, RLENGTH)
  sub(/^.*:[ ]*/, "", seg)
  return seg + 0
}

# A note filename that survives every filesystem Obsidian runs on.
function safestem(s, fallback,   out) {
  out = s
  gsub(/[\/\\:*?"<>|#^\[\]]/, "-", out)
  gsub(/[[:cntrl:]]/, "", out)
  gsub(/-+/, "-", out)
  gsub(/^[ .-]+|[ .-]+$/, "", out)
  # A label made entirely of punctuation collapses to nothing, and a note
  # called "----" tells a reader less than the id does.
  if (out == "") out = fallback
  gsub(/[\/\\:*?"<>|#^\[\]]/, "-", out)
  gsub(/-+/, "-", out)
  gsub(/^[ .-]+|[ .-]+$/, "", out)
  if (out == "") out = "unnamed"
  if (length(out) > 80) out = substr(out, 1, 80)
  return out
}

function owned_write(name, body,   full, probe, rc) {
  full = vault "/" name
  probe = ""
  rc = (getline probe < full)
  close(full)
  if (rc >= 0 && !(name in owned)) {
    skipped[++nskipped] = name
    return 0
  }
  printf "%s", body > full
  close(full)
  written[name] = 1
  nwritten++
  return 1
}

BEGIN {
  nnodes = 0; nedges = 0; nwritten = 0; nskipped = 0
  while ((getline line < manifest) > 0) if (line != "") owned[line] = 1
  close(manifest)
}

/"id"[ ]*:/ {
  nnodes++
  nid[nnodes]    = jval($0, "id")
  nlabel[nnodes] = jval($0, "label")
  nkind[nnodes]  = jval($0, "kind")
  npath[nnodes]  = jval($0, "path")
  ndesc[nnodes]  = jval($0, "description")
  nissue[nnodes] = jval($0, "issue")
  ntier[nnodes]  = jint($0, "tier")
  nlines[nnodes] = jint($0, "lines")
  nmatch[nnodes] = jint($0, "matches")
  idx[nid[nnodes]] = nnodes
  next
}

/"source"[ ]*:/ {
  nedges++
  esrc[nedges]  = jval($0, "source")
  edst[nedges]  = jval($0, "target")
  erel[nedges]  = jval($0, "relation")
  econf[nedges] = jval($0, "confidence")
  next
}

/"generated"[ ]*:/ { if (stamp == "") stamp = jval($0, "generated"); next }

END {
  if (nnodes == 0) {
    print "context-graph: graph.json has no nodes - nothing to export" > "/dev/stderr"
    exit 1
  }

  # A glob is not a note. "src/api/**" makes a filename no filesystem wants
  # and a title no reader gains from; what matters about a glob is how many
  # files it actually matches, and that belongs in the rule that claims it.
  # The HTML view keeps them as nodes, where the reach is the whole point.
  for (i = 1; i <= nnodes; i++) if (nkind[i] == "path") skipnote[i] = 1

  # Stable, collision-free note names.
  for (i = 1; i <= nnodes; i++) {
    if (skipnote[i]) continue
    base = safestem(nlabel[i] == "" ? nid[i] : nlabel[i], nkind[i] "-" nnodes_seq++)
    stem = base
    if (base in usedstem) { usedstem[base]++; stem = base " (" usedstem[base] ")" }
    else usedstem[base] = 1
    note[i] = stem
  }

  KINDDESC["tier1"]     = "Loaded on every session and every subagent. The most expensive place knowledge can live."
  KINDDESC["rule"]      = "Tier 2. Loads only when a file matching its paths is touched."
  KINDDESC["path"]      = "A glob some rule claims. The match count is what decides whether that rule can ever fire."
  KINDDESC["knowledge"] = "Tier 3 reference. Costs nothing until something looks it up - and nothing will, unless something links here."
  KINDDESC["skill"]     = "Tier 3 procedure. Loads only when its description matches what was asked."
  KINDDESC["command"]   = "A slash command."
  KINDDESC["agent"]     = "A subagent definition."
  KINDDESC["finding"]   = "A working log entry. Survives compaction because it is on disk."
  KINDDESC["doc"]       = "An ordinary repo document that something in the layout cites as its authority."
  KINDDESC["file"]      = "A source file touched during a recorded session."
  KINDDESC["session"]   = "A recorded session or subagent thread."
  KINDDESC["hook"]      = "A hook configuration."

  for (i = 1; i <= nnodes; i++) {
    if (skipnote[i]) continue
    b = "---\n"
    b = b "tags:\n  - context-kit/" nkind[i] "\n"
    if (ntier[i] != "" && ntier[i] > 0) b = b "  - context-kit/tier" ntier[i] "\n"
    if (nissue[i] != "") b = b "  - context-kit/flagged\n"
    b = b "kind: \"" nkind[i] "\"\n"
    if (npath[i] != "") b = b "source: \"" npath[i] "\"\n"
    b = b "generated_by: context-kit\n"
    b = b "---\n\n# " nlabel[i] "\n\n"
    if (KINDDESC[nkind[i]] != "") b = b "*" KINDDESC[nkind[i]] "*\n\n"
    if (ndesc[i] != "") b = b "**Fires on:** " ndesc[i] "\n\n"
    if (npath[i] != "") b = b "**Source:** `" npath[i] "`\n\n"
    if (nlines[i] != "" && nlines[i] > 0) b = b "**Lines:** " nlines[i] "\n\n"
    if (nmatch[i] != "") b = b "**Matches:** " nmatch[i] " file" (nmatch[i] == 1 ? "" : "s") " in this repo\n\n"
    if (nissue[i] != "") b = b "> [!warning] Flagged\n> " nissue[i] "\n\n"

    out_n = 0; in_n = 0; cov_n = 0
    outb = ""; inb = ""; cov = ""
    for (j = 1; j <= nedges; j++) {
      if (esrc[j] == nid[i] && (edst[j] in idx)) {
        d = idx[edst[j]]
        if (skipnote[d]) {
          cov = cov "- `" nlabel[d] "` — " (nmatch[d] == "" ? "?" : nmatch[d]) \
                " file" (nmatch[d] == 1 ? "" : "s") "\n"
          cov_n++
          continue
        }
        outb = outb "- " erel[j] " → [[" note[d] "]] <sub>" econf[j] "</sub>\n"
        out_n++
      } else if (edst[j] == nid[i] && (esrc[j] in idx) && !skipnote[idx[esrc[j]]]) {
        inb = inb "- [[" note[idx[esrc[j]]] "]] → " erel[j] " <sub>" econf[j] "</sub>\n"
        in_n++
      }
    }
    if (cov_n) {
      b = b "## Covers\n\nThis rule loads only when one of these is touched. "
      b = b "A glob matching nothing is a rule that can never fire.\n\n" cov "\n"
    }
    if (out_n) b = b "## Points at\n\n" outb "\n"
    if (in_n)  b = b "## Pointed at by\n\n" inb "\n"
    if (!out_n && !in_n && !cov_n) {
      b = b "## Connections\n\nNone. Nothing in the layout links here and it links nowhere, "
      b = b "so nothing will find it by following a trail.\n\n"
    }
    b = b "---\n\n[[_MAP|Back to the map]] · generated " stamp "\n"
    owned_write(note[i] ".md", b)
  }

  # The index.
  m = "---\ntags:\n  - context-kit/map\ngenerated_by: context-kit\n---\n\n"
  m = m "# Context map\n\n"
  m = m "The context layout of `" root "`, as of " stamp ". "
  m = m "Open this folder as an Obsidian vault and use the graph view; every note "
  m = m "is wikilinked, so the graph view shows the same structure the HTML viewer does.\n\n"
  nflag = 0
  for (i = 1; i <= nnodes; i++) if (nissue[i] != "" && !skipnote[i]) nflag++
  if (nflag) {
    m = m "## Flagged (" nflag ")\n\n"
    for (i = 1; i <= nnodes; i++)
      if (nissue[i] != "" && !skipnote[i]) m = m "- [[" note[i] "]] — " nissue[i] "\n"
    m = m "\n"
  }
  ORDER = "tier1 rule knowledge skill command agent finding doc file session hook"
  nk = split(ORDER, KO, " ")
  for (k = 1; k <= nk; k++) {
    cnt = 0; sect = ""
    for (i = 1; i <= nnodes; i++) {
      if (nkind[i] != KO[k] || skipnote[i]) continue
      cnt++
      sect = sect "- [[" note[i] "]]" (ndesc[i] != "" ? " — " substr(ndesc[i], 1, 100) : "") "\n"
    }
    if (cnt) m = m "## " KO[k] " (" cnt ")\n\n" sect "\n"
  }
  owned_write("_MAP.md", m)

  # Rewrite the manifest from what exists now, so a note deleted upstream
  # stops being claimed and a note you later edit by hand is still ours to
  # refresh. Anything skipped is recorded as yours and stays that way.
  mf = ""
  for (n in written) mf = mf n "\n"
  printf "%s", mf > manifest
  close(manifest)

  printf "wrote %d note%s to %s\n", nwritten, (nwritten == 1 ? "" : "s"), vault
  if (nskipped) {
    printf "skipped %d file%s already in that folder that context-kit did not create:\n",
      nskipped, (nskipped == 1 ? "" : "s")
    for (i = 1; i <= nskipped && i <= 10; i++) printf "  %s\n", skipped[i]
    if (nskipped > 10) printf "  ... and %d more\n", nskipped - 10
  }
}
