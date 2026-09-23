# Deterministic context cost per task, per arm. No model involved.
#
# -v arm=a|b  -v dest=<arm dir>  -v touched="f1,f2,..."
#
# Arm B always loads the whole CLAUDE.md. Arm A loads CLAUDE.md plus only the
# rules whose paths: glob matches a file the task touches. knowledge/ counts
# zero because tier 3 is reached by lookup - that IS the claim under test, and
# the writeup says so rather than hiding it in the arithmetic.
function globre(g,   out, i, c, n) {
  out = "^"; n = length(g); i = 1
  while (i <= n) {
    c = substr(g, i, 1)
    if (c == "*") {
      if (substr(g, i, 3) == "**/") { out = out "([^/]+/)*"; i += 3; continue }
      if (substr(g, i, 2) == "**")  { out = out ".*";        i += 2; continue }
      out = out "[^/]*"; i++; continue
    }
    if (c == "?") { out = out "[^/]"; i++; continue }
    # A character-class regex literal here breaks busybox awk 1.36's loader
    # outright ("Invalid content of \{\}"), whether or not it is reached -
    # see scripts/common.awk's globre(). Same fix: a plain string search.
    if (index(".[]()+^$|\\{}", c) > 0) { out = out "\\" c; i++; continue }
    out = out c; i++
  }
  return out "$"
}
function filesize(p,   c, line) {
  c = 0
  while ((getline line < p) > 0) c += length(line) + 1
  close(p)
  return c
}
BEGIN {
  ntouch = split(touched, T, ",")
  total = 0; nfiles = 0; detail = ""

  cm = dest "/CLAUDE.md"
  b = filesize(cm)
  total += b; nfiles++
  detail = "CLAUDE.md:" b

  if (arm == "a") {
    cmd = "ls " dest "/.claude/rules/*.md 2>/dev/null"
    while ((cmd | getline rf) > 0) {
      # read the paths: globs out of the frontmatter
      inpaths = 0; matched = 0
      while ((getline line < rf) > 0) {
        if (line ~ /^paths:/) { inpaths = 1; continue }
        if (inpaths && line ~ /^[ \t]*-[ \t]*/) {
          g = line
          sub(/^[ \t]*-[ \t]*/, "", g); gsub(/^"|"$/, "", g)
          re = globre(g)
          for (i = 1; i <= ntouch; i++) if (T[i] ~ re) matched = 1
          continue
        }
        if (inpaths) break
      }
      close(rf)
      if (matched) {
        sz = filesize(rf)
        total += sz; nfiles++
        nm = rf; sub(/.*\//, "", nm)
        detail = detail " " nm ":" sz
      }
    }
    close(cmd)
  }
  printf "%s\t%d\t%d\t%d\t%s\n", arm, total, int(total / 4), nfiles, detail
}
