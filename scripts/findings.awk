# findings/*.md -> findings/LESSONS.md. POSIX awk, deterministic, no LLM.
#
# -v today=YYYY-MM-DD    anchors the time decay; passed in so the output is
#                        byte-stable for a given input and a given day
# -v halflife=30         days after which a signal counts half
# -v mincorr=2           distinct useful entries before a source is "preferred"
#
# The aggregation - signed outcomes, time decay, a corroboration floor, and
# the preferred / tentative / contested / dead-end split - is adapted from
# graphify's `reflect` (Apache-2.0, Graphify Labs). What it reads is
# different: graphify files one document per saved answer, this reads the
# append-only per-investigation logs that findings/README.md already
# prescribes, so nothing about the existing convention changes.
#
# Two rules do the real work. A single entry never mints a trusted source -
# one confident note is how a wrong answer becomes a fact. And a signal
# decays, so a dead end found last week outweighs a success from March; the
# alternative is a ledger that gets more confident the more out of date it is.

function daynum(y, m, d,   era, yoe, doy, doe) {
  y += 0; m += 0; d += 0
  if (y < 1 || m < 1 || m > 12 || d < 1) return -1
  y -= (m <= 2)
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}

function parsedate(s,   a) {
  if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return -1
  split(substr(s, 1, 10), a, "-")
  return daynum(a[1], a[2], a[3])
}

function weight(datestr,   dn, age) {
  dn = parsedate(datestr)
  if (dn < 0 || nowday < 0) return 1
  age = nowday - dn
  if (age < 0) age = 0
  return exp(log(0.5) * age / halflife)
}

function trimfield(s) {
  sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
  return s
}

# Record one entry's signal against each source it cites.
function flush(   i, n, arr, src, w, sign) {
  if (e_date == "" && e_question == "") return
  nent++
  oc = (e_outcome == "" ? "unmarked" : e_outcome)
  counts[oc]++
  sign = (oc == "useful") ? 1 : ((oc == "dead_end" || oc == "corrected") ? -1 : 0)
  if (sign != 0) {
    w = weight(e_date)
    n = split(e_sources, arr, ",")
    for (i = 1; i <= n; i++) {
      src = trimfield(arr[i])
      gsub(/^`|`$/, "", src)
      src = trimfield(src)
      if (src == "") continue
      if (!(src in seensrc)) { seensrc[src] = 1; srcorder[++nsrc] = src }
      if (sign > 0) { pos[src]++; score[src] += w }
      else          { neg[src]++; score[src] -= w }
      if (e_date > last[src]) last[src] = e_date
    }
  }
  if (oc == "dead_end") {
    k = e_question "\x01" e_sources
    if (!(k in deadseen)) {
      deadseen[k] = 1
      ndead++
      dq[ndead] = e_question; ds[ndead] = e_sources; dd[ndead] = e_date
      dfile[ndead] = curfile
    }
  } else if (oc == "corrected") {
    k = e_question "\x01" e_correction
    if (!(k in corrseen)) {
      corrseen[k] = 1
      ncorr++
      cq[ncorr] = e_question; cc[ncorr] = e_correction; cd[ncorr] = e_date
      cfile[ncorr] = curfile
    }
  }
  e_date = ""; e_question = ""; e_outcome = ""; e_correction = ""; e_sources = ""
}

BEGIN {
  if (halflife == "" || halflife + 0 <= 0) halflife = 30
  if (mincorr == "" || mincorr + 0 < 1) mincorr = 2
  nowday = parsedate(today)
  nent = 0; nsrc = 0; ndead = 0; ncorr = 0; nfiles = 0
  counts["useful"] = 0; counts["dead_end"] = 0
  counts["corrected"] = 0; counts["unmarked"] = 0
}

FNR == 1 {
  flush()
  curfile = FILENAME
  sub(/.*\//, "", curfile)
  if (curfile != "LESSONS.md") { nfiles++; filelist[nfiles] = curfile }
}

curfile == "LESSONS.md" { next }

/^##[ \t]/ {
  flush()
  hdr = $0
  sub(/^##[ \t]+/, "", hdr)
  if (match(hdr, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) {
    e_date = substr(hdr, RSTART, RLENGTH)
    e_title = trimfield(substr(hdr, RSTART + RLENGTH))
    sub(/^[-\xe2\x80\x94 ]+/, "", e_title)
  } else {
    e_date = ""
    e_title = hdr
  }
  next
}

/^\*\*[A-Za-z]+:\*\*/ {
  key = $0
  sub(/^\*\*/, "", key); sub(/:\*\*.*$/, "", key)
  val = $0
  sub(/^\*\*[A-Za-z]+:\*\*[ \t]*/, "", val)
  val = trimfield(val)
  k = tolower(key)
  if (k == "question")        e_question = val
  else if (k == "outcome")    { e_outcome = tolower(val); gsub(/[^a-z_]/, "", e_outcome) }
  else if (k == "correction") e_correction = val
  else if (k == "sources")    e_sources = val
  else if (k == "finding" && e_question == "") e_question = val
  next
}

END {
  flush()
  if (nent == 0) {
    print "# Lessons"
    print ""
    print "_No findings entries yet. Append one to a file in `findings/` with an"
    print "`**Outcome:**` line and re-run._"
    exit 0
  }

  for (i = 1; i <= nsrc; i++) {
    s = srcorder[i]
    sc = int(score[s] * 1000000 + (score[s] >= 0 ? 0.5 : -0.5)) / 1000000
    if (pos[s] > 0 && neg[s] > 0)                        bucket[s] = "contested"
    else if (pos[s] >= mincorr && sc > 0)                bucket[s] = "preferred"
    else if (pos[s] > 0)                                 bucket[s] = "tentative"
    else                                                 bucket[s] = "burned"
    rscore[s] = sc
  }

  print "# Lessons"
  print ""
  printf "_Generated by `context-kit` from %d marked entr%s across %d file%s in `findings/`.\n",
    nent, (nent == 1 ? "y" : "ies"), nfiles, (nfiles == 1 ? "" : "s")
  printf "Deterministic, no model involved. Signals decay with a %g-day half-life and a\n", halflife
  printf "source needs %d corroborating entries before it is preferred. Orientation only -\n", mincorr
  print "verify before relying, and revisit a dead end if the code has moved since._"
  print ""
  print "## Summary"
  print ""
  printf "- %d useful · %d dead end%s · %d corrected · %d unmarked\n",
    counts["useful"], counts["dead_end"], (counts["dead_end"] == 1 ? "" : "s"),
    counts["corrected"], counts["unmarked"]
  print ""

  emit_bucket("preferred", "Preferred sources", \
    "Corroborated by " mincorr "+ useful entries. Start here.")
  emit_bucket("tentative", "Tentative", \
    "Useful once, not yet corroborated. Verify before relying on it.")
  emit_bucket("contested", "Contested", \
    "Both useful and not. The decayed score decides, so recency wins.")
  emit_bucket("burned", "Negative signal only", \
    "Every entry citing these was a dead end or a correction. That is a "     \
    "statement about what was relied on, not about the file: cite in "        \
    "**Sources** what you actually leaned on, including what misled you.")

  if (ndead) {
    print "## Known dead ends"
    print ""
    print "Already walked. Do not re-derive these."
    print ""
    for (i = 1; i <= ndead; i++) {
      line = "- \"" dq[i] "\""
      if (ds[i] != "") line = line " — " ds[i]
      if (dd[i] != "") line = line " _(" dd[i] ", " dfile[i] ")_"
      print line
    }
    print ""
  }
  if (ncorr) {
    print "## Corrections"
    print ""
    print "These were wrong once. The second column is what turned out to be true."
    print ""
    for (i = 1; i <= ncorr; i++) {
      line = "- \"" cq[i] "\" → " (cc[i] == "" ? "_no correction recorded_" : cc[i])
      if (cd[i] != "") line = line " _(" cd[i] ", " cfile[i] ")_"
      print line
    }
    print ""
  }
  if (nfiles) {
    print "## Sources"
    print ""
    for (i = 1; i <= nfiles; i++) print "- `findings/" filelist[i] "`"
    print ""
  }
}

function emit_bucket(name, title, blurb,   i, s, any, keys, nk, j, tmp) {
  nk = 0
  for (i = 1; i <= nsrc; i++) if (bucket[srcorder[i]] == name) keys[++nk] = srcorder[i]
  if (!nk) return
  # Highest absolute score first, then alphabetically - a stable order, so a
  # re-run with no new entries produces a byte-identical file.
  for (i = 2; i <= nk; i++) {
    tmp = keys[i]
    for (j = i - 1; j >= 1 && cmp_src(tmp, keys[j]) < 0; j--) keys[j + 1] = keys[j]
    keys[j + 1] = tmp
  }
  print "## " title
  print ""
  print blurb
  print ""
  for (i = 1; i <= nk; i++) {
    s = keys[i]
    line = "- `" s "` — " (pos[s] + 0) "× useful"
    if (neg[s] + 0) line = line ", " (neg[s] + 0) "× dead end or corrected"
    line = line sprintf(" (score %+.2f", rscore[s])
    if (last[s] != "") line = line ", latest " last[s]
    line = line ")"
    print line
  }
  print ""
}

function cmp_src(a, b,   sa, sb) {
  sa = rscore[a]; sb = rscore[b]
  if (sa > sb) return -1
  if (sa < sb) return 1
  if (a < b) return -1
  if (a > b) return 1
  return 0
}
