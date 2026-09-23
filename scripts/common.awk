# Shared awk helpers: path utilities, the per-language extension table, the
# comment/string-stripping lexer, and frontmatter parsing. Composed FIRST
# with `-f`, ahead of the script that uses them - e.g.
# `awk -f common.awk -f code-graph.awk` or
# `awk -f common.awk -f context-graph.awk`. POSIX awk, portable to mawk,
# gawk and busybox awk.
#
# Every function here becomes global in whatever it is composed with, and
# mawk treats a duplicate function definition as a parse-time error - so no
# file composed with this one may redefine any name below.

function basename(p,   b) { b = p; sub(/.*\//, "", b); return b }
function dirname(p,   d)  { d = p; if (d !~ /\//) return ""; sub(/\/[^\/]*$/, "", d); return d }
function stripext(p,   b) { b = p; sub(/\.[^.\/]*$/, "", b); return b }
function extof(p,   b)    { b = p; if (b !~ /\.[^.\/]*$/) return ""; sub(/.*\./, "", b); return tolower(b) }

# Collapse "." and ".." segments. A path that climbs above the root is
# rejected outright rather than clamped, because a clamped path silently
# resolves to the wrong file.
function norm(p,   n, parts, out, i, k) {
  gsub(/\/+/, "/", p)
  sub(/^\.\//, "", p)
  n = split(p, parts, "/")
  k = 0
  for (i = 1; i <= n; i++) {
    if (parts[i] == "" || parts[i] == ".") continue
    if (parts[i] == "..") {
      if (k == 0) return ""
      k--
      continue
    }
    out[++k] = parts[i]
  }
  p = ""
  for (i = 1; i <= k; i++) p = p (i > 1 ? "/" : "") out[i]
  return p
}

function lang_of(e) {
  if (e == "js" || e == "jsx" || e == "mjs" || e == "cjs" || e == "ts" ||
      e == "tsx" || e == "mts" || e == "cts" || e == "vue" || e == "svelte" ||
      e == "astro") return "js"
  if (e == "py" || e == "pyi") return "py"
  if (e == "go") return "go"
  if (e == "java" || e == "kt" || e == "kts" || e == "scala" || e == "groovy") return "jvm"
  if (e == "cs") return "cs"
  if (e == "csproj" || e == "fsproj" || e == "vbproj") return "proj"
  if (e == "rs") return "rs"
  if (e == "rb") return "rb"
  if (e == "php") return "php"
  if (e == "c" || e == "h" || e == "cpp" || e == "hpp" || e == "cc" ||
      e == "hh" || e == "cxx" || e == "hxx" || e == "m" || e == "mm") return "c"
  if (e == "sh" || e == "bash") return "sh"
  return ""
}

# Extensions tried when a specifier omits one.
function exts_for(lang) {
  if (lang == "js") return ".ts .tsx .js .jsx .mjs .cjs .mts .cts .d.ts .d.mts .d.cts .vue .svelte .astro .json"
  if (lang == "py") return ".py .pyi"
  if (lang == "rs") return ".rs"
  if (lang == "rb") return ".rb"
  if (lang == "php") return ".php"
  if (lang == "jvm") return ".java .kt .kts .scala .groovy"
  if (lang == "c") return ".h .hpp .hh .hxx .c .cpp .cc .cxx"
  if (lang == "cs") return ".cs"
  if (lang == "sh") return ".sh .bash"
  return ""
}

# --- comment and string stripping -------------------------------------------
# A commented-out import and an import inside a string literal are the two
# ways a line matcher invents a dependency that does not exist. Both are
# removed here, by scanning characters with quote state, before any pattern
# runs. `blockstate` persists across lines so a /* */ or a docstring spanning
# lines keeps its whole body out.
# Also sets the global `strmask`: one character per character of the returned
# line, "S" where that position is INSIDE a string body. The contents of
# strings have to be kept - a module specifier IS a string - so an unanchored
# pattern like require(...) cannot tell a real call from one quoted inside a
# template literal. The mask is how it tells.
function decomment(line, lang,   i, n, c, c2, c3, out, q, rest, idx, t, tag) {
  out = ""
  strmask = ""
  n = length(line)

  # --- resume an open block ---------------------------------------------
  if (blockstate == 1) {                    # inside /* */
    idx = index(line, "*/")
    if (idx == 0) return ""
    blockstate = 0
    i = idx + 2
  } else if (blockstate == 2) {             # inside an inline-terminated block string
    idx = index(line, blockq)
    if (idx == 0) return ""
    blockstate = 0
    i = idx + length(blockq)
  } else if (blockstate == 3) {             # inside a heredoc / nowdoc
    t = line
    sub(/^[ \t]+/, "", t); sub(/[ \t]*;?[ \t]*$/, "", t)
    if (t == blockq) blockstate = 0
    return ""                               # every line of the body is text
  } else if (blockstate == 4) {             # inside a Ruby =begin/=end block
    if (line ~ /^=end/) blockstate = 0
    return ""
  } else {
    if (lang == "rb" && line ~ /^=begin/) { blockstate = 4; return "" }
    i = 1
  }
  for (idx = 1; idx < i; idx++) { out = out " "; strmask = strmask "." }

  q = ""
  while (i <= n) {
    c  = substr(line, i, 1)
    c2 = substr(line, i, 2)
    c3 = substr(line, i, 3)

    if (q != "") {
      out = out c
      if (c == "\\") { out = out substr(line, i + 1, 1); strmask = strmask "SS"; i += 2; continue }
      if (c == q) { q = ""; strmask = strmask "." }
      else strmask = strmask "S"
      i++
      continue
    }

    # Triple-quoted block strings: Python docstrings, Java text blocks,
    # Kotlin raw strings. A wrapped import line inside one is template data.
    if ((lang == "py" || lang == "jvm") &&
        (c3 == "\"\"\"" || (lang == "py" && c3 == "'''"))) {
      blockq = c3
      rest = substr(line, i + 3)
      if (index(rest, blockq) > 0) { i = i + 3 + index(rest, blockq) + 2; continue }
      blockstate = 2
      return out
    }

    # C++11 raw string: R"delim( ... )delim". Its body is data even when a
    # line starts in column zero and reads exactly like a directive, and
    # only state carried across lines keeps that line out of the graph.
    if (lang == "c" && c2 == "R\"") {
      tag = ""
      idx = i + 2
      while (idx <= n && substr(line, idx, 1) != "(" && length(tag) < 16) {
        tag = tag substr(line, idx, 1); idx++
      }
      if (idx <= n && substr(line, idx, 1) == "(") {
        blockq = ")" tag "\""
        rest = substr(line, idx + 1)
        if (index(rest, blockq) > 0) { i = idx + index(rest, blockq) + length(blockq); continue }
        blockstate = 2
        return out
      }
    }

    # Ruby and PHP heredocs / nowdocs. `<<~`, `<<-` and `<<<` are
    # unambiguous; a bare `<<` counts only before a quote or a capital, so
    # the append operator (`list << item`) is not mistaken for one.
    if (lang == "rb" && c2 == "<<") {
      tag = ""
      idx = i + 2
      if (substr(line, idx, 1) == "~" || substr(line, idx, 1) == "-") idx++
      else if (substr(line, idx, 1) !~ /["'A-Z]/) { out = out c; strmask = strmask "."; i++; continue }
      if (substr(line, idx, 1) == "'" || substr(line, idx, 1) == "\"") idx++
      while (idx <= n && substr(line, idx, 1) ~ /[A-Za-z0-9_]/) { tag = tag substr(line, idx, 1); idx++ }
      if (tag != "") { blockq = tag; blockstate = 3; return out }
    }
    if (lang == "php" && c3 == "<<<") {
      tag = ""
      idx = i + 3
      if (substr(line, idx, 1) == "'" || substr(line, idx, 1) == "\"") idx++
      while (idx <= n && substr(line, idx, 1) ~ /[A-Za-z0-9_]/) { tag = tag substr(line, idx, 1); idx++ }
      if (tag != "") { blockq = tag; blockstate = 3; return out }
    }

    if (c2 == "/*" && (lang == "js" || lang == "c" || lang == "cs" || lang == "rs" ||
                       lang == "jvm" || lang == "php" || lang == "go")) {
      rest = substr(line, i + 2)
      if (index(rest, "*/") > 0) { i = i + 2 + index(rest, "*/") + 1; out = out " "; strmask = strmask "."; continue }
      blockstate = 1
      return out
    }
    if (c2 == "//" && (lang == "js" || lang == "c" || lang == "cs" || lang == "rs" ||
                       lang == "jvm" || lang == "php" || lang == "go")) return out
    if (c == "#" && (lang == "py" || lang == "rb" || lang == "sh" || lang == "php")) return out

    # A JS template literal that does not close on this line keeps running.
    # Its body is data, so a require(...) or an import line inside it is
    # documentation and not a dependency.
    if (c == "`" && (lang == "js" || lang == "go")) {
      rest = substr(line, i + 1)
      if (rest ~ /`/) { q = c; out = out c; strmask = strmask "."; i++; continue }
      blockq = "`"
      blockstate = 2
      return out
    }

    if (c == "\"" || c == "'") { q = c; out = out c; strmask = strmask "."; i++; continue }
    out = out c
    strmask = strmask "."
    i++
  }
  return out
}

# True when the match that begins at 1-based position `pos` starts inside a
# string body, and is therefore quoted text rather than code.
function in_string(pos) { return (substr(strmask, pos, 1) == "S") }

# Translate a paths: glob into an ERE. POSIX awk has no fnmatch, and the
# difference between `src/*` and `src/**` is the whole point of tier 2 - a
# glob that silently matches everything is a tier-1 entry wearing a costume.
function globre(g,   out, i, c, n) {
  out = "^"
  n = length(g)
  i = 1
  while (i <= n) {
    c = substr(g, i, 1)
    if (c == "*") {
      if (substr(g, i, 3) == "**/") { out = out "([^/]+/)*"; i += 3; continue }
      if (substr(g, i, 2) == "**")  { out = out ".*";        i += 2; continue }
      out = out "[^/]*"; i++; continue
    }
    if (c == "?") { out = out "[^/]"; i++; continue }
    # A character-class regex literal here (`c ~ /[.\[\]()+^$|\\{}]/`) is
    # what context-graph.awk used before this moved: busybox awk 1.36
    # refuses to even load a program containing that literal ("Invalid
    # content of \{\}"), whether or not it is ever reached. A plain string
    # search tests the same set of metacharacters without a regex at all.
    if (index(".[]()+^$|\\{}", c) > 0) { out = out "\\" c; i++; continue }
    out = out c
    i++
  }
  return out "$"
}

# --- frontmatter -------------------------------------------------------------
# One line of a context file's YAML frontmatter: the opening/closing `---`,
# a `key: value` pair, or a block-list item (`  - "a/**"`) belonging to the
# most recent list key. Owns (and the caller must reset before the first
# line) the parser state infm/fmdone/inlist/listkey/body_lines and the
# fm_desc/fm_name/fm_outcome/fm_paths globals it fills in - fm_paths holds
# every `paths:` glob seen, newline-joined, each glob followed by "\n".
# `body_lines` is read, not written here except implicitly via the caller:
# it is how the frontmatter opener is told apart from a `---` thematic break
# later in the body - frontmatter only counts before any real content line.
# Returns 1 when the line was consumed as frontmatter (the caller should not
# treat it as body text), 0 otherwise.
function fm_line(line,   tmp, k, rest, v, n, arr, m) {
  if (!fmdone && line ~ /^---[ \t]*$/) {
    if (!infm && body_lines == 0) { infm = 1; return 1 }
    if (infm) { infm = 0; fmdone = 1; inlist = 0; return 1 }
  }
  if (infm) {
    if (line ~ /^[ \t]*-[ \t]*/ && inlist) {
      tmp = line
      sub(/^[ \t]*-[ \t]*/, "", tmp)
      gsub(/^["']|["'][ \t]*$/, "", tmp)
      sub(/[ \t]+$/, "", tmp)
      if (tmp != "" && listkey == "paths") fm_paths = fm_paths tmp "\n"
      return 1
    }
    inlist = 0
    if (match(line, /^[A-Za-z_][A-Za-z0-9_-]*:/)) {
      k = substr(line, 1, RLENGTH - 1)
      rest = substr(line, RLENGTH + 1)
      sub(/^[ \t]+/, "", rest)
      sub(/[ \t]+$/, "", rest)
      gsub(/^["']|["']$/, "", rest)
      if (rest == "") { inlist = 1; listkey = k; return 1 }
      if (k == "description") fm_desc = rest
      else if (k == "name") fm_name = rest
      else if (k == "outcome") fm_outcome = rest
      else if (k == "paths") {
        # inline flow list: paths: ["a/**", "b/**"]
        tmp = rest
        gsub(/^\[|\]$/, "", tmp)
        n = split(tmp, arr, /[ \t]*,[ \t]*/)
        for (m = 1; m <= n; m++) {
          v = arr[m]
          gsub(/^["' \t]+|["' \t]+$/, "", v)
          if (v != "") fm_paths = fm_paths v "\n"
        }
      }
    }
    return 1
  }
  return 0
}

# Just the `paths:` globs from a context file's frontmatter, newline-joined -
# what scanfile()'s fm_paths holds after a full pass, without reading the
# rest of the file. Strips a trailing \r so a file saved on Windows still
# parses.
function rule_paths(path,   line, full) {
  fm_paths = ""
  full = (path ~ /^\//) ? path : root "/" path
  infm = 0; fmdone = 0; inlist = 0; listkey = ""; body_lines = 0
  while ((getline line < full) > 0) {
    sub(/\r$/, "", line)
    if (fm_line(line)) { if (fmdone) break; continue }
    if (line ~ /^[ \t]*$/) continue
    if (line ~ /^[ \t]*<!--/) continue
    body_lines++
  }
  close(full)
  return fm_paths
}
