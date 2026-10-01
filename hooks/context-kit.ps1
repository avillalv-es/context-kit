# context-kit hook entrypoint. PowerShell twin of context-kit.sh.
#
# Usage: context-kit.ps1 session|subagent|mode|signal|event
#
# Claude Code uses Git Bash on Windows when it is installed and falls back to
# PowerShell otherwise. Both scripts are registered for every event; each is
# idempotent and exits silently when it is not the active shell, so exactly one
# produces output.
#
# Fails open, always. Every error path exits 0 with no output.
# Patterns adapted from ponytail (MIT, Dietrich Gebert) and graphify
# (Apache-2.0, Graphify Labs). See NOTICE.

$ErrorActionPreference = 'SilentlyContinue'

$Action = if ($args.Count -gt 0) { $args[0] } else { '' }

if ($env:CONTEXT_KIT_OFF -eq '1') { exit 0 }

$Root = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else { Split-Path -Parent $PSScriptRoot }
$Data = if ($env:CLAUDE_PLUGIN_DATA) { $env:CLAUDE_PLUGIN_DATA } else { Join-Path $HOME '.claude\context-kit' }
$Proj = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $PWD.Path }
$Rules = Join-Path $Root 'hooks\rules.md'
$Native = Join-Path $Root 'knowledge\platform-native.md'
$Threshold = 3

# Reject paths unsafe to hand to a shell. Ponytail isShellSafe.
if ($Data -notmatch '^[A-Za-z0-9 _.\-:/\\~]+$') {
  $Data = Join-Path $HOME '.claude\context-kit'
}

# Stable per-project key, matching the sh script in spirit (not in value; the
# two shells never share a data directory on the same machine).
$Hash = [Math]::Abs($Proj.ToLower().GetHashCode()).ToString()

function Resolve-Level {
  $l = $env:CONTEXT_KIT_LEVEL
  if (-not $l) {
    $f = Join-Path $Data 'level'
    if (Test-Path $f) { $l = (Get-Content $f -First 1).Trim() }
  }
  if ($l -in @('lite', 'full', 'ultra', 'off')) { return $l }
  return 'full'
}

function Write-HookOutput([string]$EventName, [string]$Text) {
  if (-not $Text) { exit 0 }
  $payload = @{
    hookSpecificOutput = @{
      hookEventName    = $EventName
      additionalContext = $Text
    }
  }
  $payload | ConvertTo-Json -Depth 5 -Compress
}

# Stdin can only be drained once, and the event handler needs several fields
# from the same payload, so the parse is cached rather than repeated.
$script:HookInput = $null
$script:HookInputRead = $false
function Get-HookInput {
  if ($script:HookInputRead) { return $script:HookInput }
  $script:HookInputRead = $true
  $raw = [Console]::In.ReadToEnd()
  if (-not $raw) { return $null }
  try { $script:HookInput = $raw | ConvertFrom-Json } catch { $script:HookInput = $null }
  return $script:HookInput
}

# Takes a bare key or a dotted path, matching the sh side. ConvertFrom-Json
# has already decoded the escapes, so there is no decoder here to mirror -
# only the scoping, so a "command" key inside tool_response cannot win.
function Get-JsonField([string]$Name) {
  $obj = Get-HookInput
  if (-not $obj) { return '' }
  try {
    $cur = $obj
    foreach ($part in $Name.Split('.')) {
      if ($null -eq $cur) { return '' }
      $cur = $cur.$part
    }
    if ($null -eq $cur) { return '' }
    if ($cur -is [array] -or $cur -is [psobject] -and -not ($cur -is [string])) {
      if (-not ($cur -is [string])) { return '' }
    }
    return [string]$cur
  } catch { return '' }
}

# Lexical only - Resolve-Path would follow a link and touch the disk. Returns
# '' for anything that lands outside the project, which is the guard: the old
# code relativized absolute paths and let a RELATIVE ../../etc/passwd through
# untouched, straight past the check that rejects the absolute form.
function Resolve-ProjectRelative([string]$Path, [string]$Base) {
  if (-not $Path) { return '' }
  $p = $Path -replace '\\', '/'
  $np = ($Proj -replace '\\', '/').TrimEnd('/')
  $b = if ($Base) { ($Base -replace '\\', '/').TrimEnd('/') } else { $np }
  if ($p -notmatch '^([A-Za-z]:)?/') { $p = "$b/$p" }
  $drive = ''
  if ($p -match '^([A-Za-z]:)(/.*)$') { $drive = $Matches[1]; $p = $Matches[2] }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($seg in $p.Split('/')) {
    if ($seg -eq '' -or $seg -eq '.') { continue }
    if ($seg -eq '..') {
      if ($out.Count -eq 0) { return '' }
      $out.RemoveAt($out.Count - 1); continue
    }
    $out.Add($seg)
  }
  $abs = $drive + '/' + ($out -join '/')
  if (-not $abs.StartsWith($np + '/', [StringComparison]::OrdinalIgnoreCase)) { return '' }
  return $abs.Substring($np.Length + 1)
}

# Filters rules.md to the active level. Lines tagged [lite]/[full]/[ultra] are
# level-specific; every other line always applies.
function Get-Ruleset([string]$Level) {
  $out = New-Object System.Collections.Generic.List[string]
  if (Test-Path $Rules) {
    $inComment = $false
    foreach ($line in (Get-Content $Rules)) {
      if ($line -match '^<!--') { $inComment = $true }
      if ($inComment) { if ($line -match '-->') { $inComment = $false }; continue }
      if ($line -match '^\[([^\]]*)\]\s*(.*)$') {
        $tags = $Matches[1] -split ','
        if ($tags -contains $Level) { $out.Add($Matches[2]) }
        continue
      }
      $out.Add($line)
    }
  } else {
    $out.Add((Get-FallbackRules))
  }
  if (Test-Path $Native) {
    $out.Add('')
    $out.Add("Before adding any dependency, check $Native - it maps common packages to the stdlib or platform feature that already covers them.")
  }
  return ($out -join "`n")
}

# Used only when rules.md is unreadable, so the ruleset never silently vanishes.
function Get-FallbackRules {
  return @'
# Lean execution

Before writing code, stop at the first rung that holds: does it need to exist
at all; is it already in this codebase; does the stdlib do it; does a native
platform feature cover it; does an installed dependency solve it; can it be one
line; only then the minimum that works. The ladder runs after you understand
the problem, never instead of it.

Grep or Glob to locate before reading; read only the ranges you need. Send wide
searches to a subagent so raw output stays out of this window.

Answer first, then at most three short lines. If the explanation is longer than
the code, delete the explanation. Requested explanation is exempt.

Never simplify away input validation at trust boundaries, error handling that
prevents data loss, security, accessibility, or anything explicitly requested.

A procedure worth repeating gets captured with the skill-capture skill, not
added to CLAUDE.md.
'@
}

# Signatures seen Threshold+ times with neither a matching skill directory nor
# a previous suggestion.
function Get-PendingRepeats {
  $sigFile = Join-Path $Data "signals\$Hash.tsv"
  if (-not (Test-Path $sigFile)) { return '' }
  $suggestedFile = Join-Path $Data "state\$Hash.suggested"
  $already = @()
  if (Test-Path $suggestedFile) { $already = @(Get-Content $suggestedFile) }

  $counts = Get-Content $sigFile |
    ForEach-Object { ($_ -split "`t")[0] } |
    Where-Object { $_ } |
    Group-Object |
    Where-Object { $_.Count -ge $Threshold } |
    Select-Object -First 5

  $found = @()
  foreach ($c in $counts) {
    $sig = $c.Name
    if (Test-Path (Join-Path $Proj ".claude\skills\$sig")) { continue }
    if ($already -contains $sig) { continue }
    $found += $sig
    $stateDir = Join-Path $Data 'state'
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force -Path $stateDir | Out-Null }
    Add-Content -Path $suggestedFile -Value $sig
  }
  return ($found -join ', ')
}

function Invoke-Session {
  $level = Resolve-Level
  $notes = @()

  # Bootstrap: offer once per project, then never nag. Repeating it every
  # session start turns a helpful hint into a nag.
  $offered = Join-Path $Data "state\$Hash.offered"
  if (-not (Test-Path $offered)) {
    $claudeMd = Join-Path $Proj 'CLAUDE.md'
    # The layout counts as present from its heading, its begin marker (the form
    # scripts/claude-sections.sh writes) or its off line.
    $hasMarker = (Test-Path $claudeMd) -and ((Get-Content $claudeMd) -match '^(## Context layout|<!-- context-kit:(begin|off) context-layout)')
    if (-not $hasMarker) {
      $notes += 'context-kit: this project has no context layout yet. Use the context-cleanup skill in Mode 0 now - it scaffolds the layout and creates or appends the CLAUDE.md block - then carry on with whatever was asked.'
      $stateDir = Join-Path $Data 'state'
      if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force -Path $stateDir | Out-Null }
      New-Item -ItemType File -Force -Path $offered | Out-Null
    }
  }

  # Managed CLAUDE.md sections: once per plugin version per project, say when
  # one is missing, outdated or still in its unmarked 0.4.x form. Skipped when
  # the offer above already asked for the whole layout. The flag is written
  # before the check so the steady state costs nothing. The check is the same
  # script the sh hook runs, so it needs an sh on PATH and is skipped quietly
  # without one. Where a policy blocks hooks this never runs, and a manual
  # /context-init does the same refresh.
  $sectionsMd = Join-Path $Proj 'CLAUDE.md'
  $sectionsSh = Join-Path $Root 'scripts\claude-sections.sh'
  if ($notes.Count -eq 0 -and (Test-Path $sectionsMd) -and (Test-Path $sectionsSh) -and (Get-Command sh -ErrorAction SilentlyContinue)) {
    $ver = ''
    try { $ver = [string](Get-Content (Join-Path $Root '.claude-plugin\plugin.json') -Raw | ConvertFrom-Json).version } catch { }
    $ver = $ver -replace '[^A-Za-z0-9.\-]', ''
    if (-not $ver) { $ver = 'unknown' }
    $flag = Join-Path $Data "state\$Hash.sections-$ver"
    if (-not (Test-Path $flag)) {
      $stateDir = Join-Path $Data 'state'
      if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force -Path $stateDir | Out-Null }
      New-Item -ItemType File -Force -Path $flag | Out-Null
      $status = & sh ($sectionsSh -replace '\\', '/') status ($sectionsMd -replace '\\', '/') 2>$null
      $stale = @($status | ForEach-Object { $p = "$_".Trim() -split ' '; if ($p.Count -ge 2 -and $p[0] -ne 'ok' -and $p[0] -ne 'off') { $p[1] } })
      if ($stale.Count) {
        $notes += "context-kit: CLAUDE.md managed sections need a refresh ($($stale -join ', ')). Run /context-init."
      }
    }
  }

  # Context sync: run the cheap first step of the context-sync skill here so
  # the session can skip it. An accelerator only: the managed Context sync
  # section of CLAUDE.md makes the session run the same check where this hook
  # does not run. It needs a ledger, so a project that never synced is left to
  # that section, and it is not flagged once because sources change between
  # sessions. It sits above the 'off' return below, so it fires at any lean
  # level. The same script the sh hook runs, so it needs an sh on PATH and is
  # skipped quietly without one. Unlike the sh twin there is no 3s cap: the
  # SessionStart timeout in hooks.json is the bound. An error adds nothing.
  $syncSh = Join-Path $Root 'scripts\context-sync.sh'
  if ((Test-Path -LiteralPath (Join-Path $Proj '.claude\context-sync.tsv')) -and (Test-Path -LiteralPath $syncSh) -and (Get-Command sh -ErrorAction SilentlyContinue)) {
    $syncOut = & sh ($syncSh -replace '\\', '/') check --root ($Proj -replace '\\', '/') 2>$null
    if ($LASTEXITCODE -eq 0) {
      $syncLines = @($syncOut | ForEach-Object { "$_" } | Where-Object { $_ -ne '' })
      if ($syncLines.Count) {
        $syncJoined = $syncLines -join "`n"
        $notes += "context-kit: context-sync check found work; go straight to step 2 of the context-sync skill with these lines:`n$syncJoined"
      } else {
        $notes += 'context-kit: context sources unchanged since last sync - skip the context-sync check this session.'
      }
    }
  }

  $repeats = Get-PendingRepeats
  if ($repeats) {
    $notes += "context-kit: these procedures repeated $Threshold+ times and no skill covers them: $repeats. Capture the genuinely repeatable ones with the skill-capture skill."
  }

  # Active PR train: a pointer and nothing more. The managed PR train section
  # of CLAUDE.md already tells the session to read any train with
  # "status: active", so this only makes the resume faster where the hook runs.
  # It is not flagged once, so it fires again after every compaction, and it
  # sits above the 'off' return below so it fires at any lean level. The status
  # line counts only inside the front matter: the first line must be '---' and
  # the scan stops at the next one. A missing directory or no match adds
  # nothing. Same ASCII wording as the sh twin.
  $handoffDir = Join-Path $Proj '.claude\handoff'
  $train = $null
  if (Test-Path -LiteralPath $handoffDir -PathType Container) {
    foreach ($f in @(Get-ChildItem -LiteralPath $handoffDir -Filter '*.md' -File | Sort-Object Name)) {
      if ($f.Length -eq 0) { continue }
      $hit = $false
      $reader = $null
      try {
        $reader = New-Object System.IO.StreamReader($f.FullName)
        $first = $true
        while ($null -ne ($line = $reader.ReadLine())) {
          if ($first) {
            $first = $false
            if ($line -cmatch '^---\s*$') { continue }
            break
          }
          if ($line -cmatch '^---\s*$') { break }
          if ($line -cmatch '^status:\s*active\s*$') { $hit = $true; break }
        }
      } catch { } finally { if ($reader) { $reader.Dispose() } }
      if ($hit) { $train = $f.Name; break }
    }
  }
  if ($train) {
    $notes += "context-kit: active PR train - read .claude/handoff/$train and continue from its next unchecked task."
  }

  # "off" still gets the notices above - only the ruleset itself is an
  # opt-in. (Previously this whole function exited before any notice was
  # computed; README.md's "off leaves bootstrap and repeat detection in
  # place" was never actually true until this check moved down here.)
  if ($level -eq 'off') {
    Write-HookOutput 'SessionStart' ($notes -join "`n")
    return
  }

  # Bootstrap (context-cleanup Mode 0/A) stamps this same ruleset into
  # CLAUDE.md so it still applies where a managed policy blocks plugin hooks
  # outright. CLAUDE.md loads every session regardless, so re-injecting it
  # here too would just double the tokens for everyone else. A section turned
  # off in CLAUDE.md (<!-- context-kit:off lean-execution -->) means the same.
  $claudeMdPath = Join-Path $Proj 'CLAUDE.md'
  $hasRuleset = (Test-Path $claudeMdPath) -and ((Get-Content $claudeMdPath) -match '^(## Lean execution|<!-- context-kit:off lean-execution -->)')
  if ($hasRuleset) {
    Write-HookOutput 'SessionStart' ($notes -join "`n")
    return
  }

  $body = Get-Ruleset $level
  $text = if ($notes.Count) { ($notes -join "`n") + "`n`n" + $body } else { $body }
  Write-HookOutput 'SessionStart' $text
}

# SessionStart context is parent-thread only and never reaches subagents, so
# without this every Task-spawned agent runs rules-unaware. SubagentStart also
# requires the hookSpecificOutput form or the context is dropped.
function Invoke-Subagent {
  $level = Resolve-Level
  if ($level -eq 'off') { exit 0 }
  Write-HookOutput 'SubagentStart' (Get-Ruleset $level)
}

# Whole-message match only. Matching these phrases anywhere in the message turns
# the ruleset off mid-task for ordinary requests like "add a normal mode toggle".
function Invoke-Mode {
  $prompt = Get-JsonField 'prompt'
  if (-not $prompt) { exit 0 }
  $clean = $prompt.ToLower().Trim().TrimEnd('.', '!', ' ')
  $new = switch ($clean) {
    '/lean lite'  { 'lite' }
    '/lean full'  { 'full' }
    '/lean ultra' { 'ultra' }
    '/lean off'   { 'off' }
    'stop lean'   { 'off' }
    'normal mode' { 'off' }
    '/lean'       { '' }
    default       { $null }
  }
  if ($null -eq $new) { exit 0 }
  if ($new) {
    if (-not (Test-Path $Data)) { New-Item -ItemType Directory -Force -Path $Data | Out-Null }
    Set-Content -Path (Join-Path $Data 'level') -Value $new
    $level = $new
  } else {
    $level = Resolve-Level
  }
  @{
    hookSpecificOutput = @{
      hookEventName     = 'UserPromptSubmit'
      additionalContext = "context-kit level is now: $level"
      systemMessage     = "context-kit: level $level"
    }
  } | ConvertTo-Json -Depth 5 -Compress
}

# Reduce a shell command to the procedure it actually runs. Twin of the awk
# `signature` in context-kit.sh; the two must agree or the same procedure gets
# two signatures across shells and never reaches the repeat threshold.
#
# Drop heredoc bodies and quoted spans, keep the first command segment, skip
# VAR=value prefixes and wrapper words with their own flags, then take the exe
# plus a bare-word subcommand. `pytest -k auth`, `sudo pytest -q` and
# `env CI=1 pytest` all collapse onto `pytest`; `npm run` stays distinct from
# `npm ci`. Adapted from graphify's _bash_invokes_search.
function Test-Preamble([string]$W) {
  return @('cd','set','export','unset','pushd','popd','source','.','shopt',
           'umask','ulimit','alias','for','while','until','if','then','elif',
           'else','fi','do','done','case','esac','function','{','}','(',')'
          ) -contains $W
}

# '<exe>-<subcommand>' for one command segment, or '' if it holds none.
function Get-SegmentSignature([string]$Seg, [string[]]$Wrappers) {
  $tokens = @($Seg.Trim() -split '\s+' | Where-Object { $_ })
  $i = 0
  while ($i -lt $tokens.Count) {
    $tok = $tokens[$i]
    if ($tok -match '^[A-Za-z_][A-Za-z0-9_]*=') { $i++; continue }
    $bare = ($tok -replace '.*[\\/]', '') -replace '\.exe$', ''
    if ($Wrappers -contains $bare.ToLower()) {
      $i++
      while ($i -lt $tokens.Count -and $tokens[$i].StartsWith('-')) { $i++ }
      continue
    }
    break
  }
  if ($i -ge $tokens.Count) { return '' }
  $exe = ((($tokens[$i]) -replace '.*[\\/]', '') -replace '\.exe$', '').ToLower()
  $arg = ''
  if ($i + 1 -lt $tokens.Count) {
    # Must be a bare word. A redirect is not a subcommand: without this,
    # 'cat > out.txt' signed as 'cat-' and 'cat <<EOF' as 'cat--'.
    $nxt = $tokens[$i + 1]
    if ($nxt -match '^[A-Za-z][A-Za-z0-9_.-]*$') { $arg = $nxt.ToLower() }
  }
  if ($arg) { return "$exe-$arg" }
  return $exe
}

function Get-CommandSignature([string]$Cmd) {
  if (-not $Cmd) { return '' }
  $wrappers = @('sudo','doas','command','exec','nohup','time','nice','ionice',
                'env','xargs','timeout','stdbuf')
  $text = $Cmd

  # Heredoc bodies never describe what ran.
  if ($text -match '<<-?\s*[''"]?([A-Za-z_][A-Za-z0-9_]*)[''"]?') {
    $tag = $Matches[1]
    $lines = $text -split "`n"
    $kept = New-Object System.Collections.Generic.List[string]
    $inBody = $false
    foreach ($line in $lines) {
      if ($inBody) { if ($line.Trim() -eq $tag) { $inBody = $false }; continue }
      $kept.Add($line)
      if ($line -match '<<-?\s*[''"]?([A-Za-z_][A-Za-z0-9_]*)[''"]?') { $tag = $Matches[1]; $inBody = $true }
    }
    $text = ($kept -join ' ')
  }

  # Anything quoted is an argument, never the executable.
  $text = $text -replace "'[^']*'", ' '
  $text = $text -replace '"[^"]*"', ' '
  # Command substitutions are arguments too, innermost first.
  for ($r = 0; $r -lt 8; $r++) {
    $before = $text
    $text = $text -replace '\$\([^()]*\)', ' '
    if ($text -eq $before) { break }
  }
  $text = $text -replace '`[^`]*`', ' '

  # Newline separates commands exactly as ';' does, and the first segment
  # that does work is the signature - not the cd or the set -e in front of
  # it. Keying on the first segment collapsed 645 distinct commands onto
  # 'cd' and 53 onto 'set', and 'set' cleared the suggestion threshold.
  foreach ($seg in ($text -split "[`n;|&]+")) {
    $sig = Get-SegmentSignature $seg $wrappers
    if ($sig) {
      $word = ($sig -split '-')[0]
      if (-not (Test-Preamble $word)) {
        return ($sig -replace '[^a-z0-9]+', '-').Trim('-')
      }
    }
  }
  # Only scaffolding: no procedure here to key on.
  return ''
}

# Project-relative paths a bash command reads. Mirrors read_paths() in the sh
# twin: gated on an allow-list of readers per segment, crude tokenizing, and
# the caller's file test as the real filter.
function Get-ReadPaths([string]$Cmd) {
  $out = New-Object System.Collections.Generic.List[string]
  if (-not $Cmd) { return $out }
  $readers = @('cat','head','tail','less','more','sed','awk','gawk','mawk',
               'grep','egrep','fgrep','rg','ag','wc','diff','cmp','od','xxd',
               'jq','yq','nl','strings','file','source','.')
  $scriptFirst = @('sed','awk','gawk','mawk','grep','egrep','fgrep','rg','ag')
  $wrappers = @('sudo','doas','command','exec','nohup','time','nice','ionice',
                'env','xargs','timeout','stdbuf')
  $text = $Cmd -replace '["'']', ' '
  for ($r = 0; $r -lt 8; $r++) {
    $before = $text
    $text = $text -replace '\$\([^()]*\)', ' '
    if ($text -eq $before) { break }
  }
  $text = $text -replace '`[^`]*`', ' '
  # Give redirect operators their own token so 'cat a>b' parses like 'cat a > b'.
  $text = $text -replace '([0-9]*>>?|<)', ' $1 '

  $base = ($Proj -replace '\\', '/').TrimEnd('/')
  foreach ($seg in ($text -split "[`n;|&]+")) {
    $tokens = @($seg.Trim() -split '\s+' | Where-Object { $_ })
    $i = 0
    while ($i -lt $tokens.Count) {
      $tok = $tokens[$i]
      if ($tok -match '^[A-Za-z_][A-Za-z0-9_]*=') { $i++; continue }
      $bare = ($tok -replace '.*[\\/]', '') -replace '\.exe$', ''
      if ($wrappers -contains $bare.ToLower()) {
        $i++
        while ($i -lt $tokens.Count -and $tokens[$i].StartsWith('-')) { $i++ }
        continue
      }
      break
    }
    if ($i -ge $tokens.Count) { continue }
    $exe = ((($tokens[$i]) -replace '.*[\\/]', '') -replace '\.exe$', '').ToLower()

    # A cd moves the base; one we cannot resolve ends the walk, because a
    # path measured from the wrong root is worse than a missing one.
    if ($exe -eq 'cd') {
      $arg = ''
      for ($j = $i + 1; $j -lt $tokens.Count; $j++) { $arg = $tokens[$j]; break }
      if (-not $arg -or $arg.Contains('$')) { return $out }
      $moved = Resolve-ProjectRelative $arg $base
      if ($moved -eq '') {
        $np = ($Proj -replace '\\', '/').TrimEnd('/')
        if ((($arg -replace '\\', '/').TrimEnd('/')) -eq $np) { $base = $np; continue }
        return $out
      }
      $base = (($Proj -replace '\\', '/').TrimEnd('/')) + '/' + $moved
      continue
    }
    if ((Test-Preamble $exe) -or -not ($readers -contains $exe)) { continue }

    $pend = ''; $skipNext = $false; $nop = 0; $sawPat = $false; $noRead = $false
    for ($j = $i + 1; $j -lt $tokens.Count; $j++) {
      $tok = $tokens[$j]
      if ($tok -match '^[0-9]*>>?$') { $pend = 'w'; continue }
      if ($tok -eq '<') { $pend = 'r'; continue }
      if ($pend -eq 'w') { $pend = ''; continue }
      if ($pend -eq 'r') {
        $pend = ''
        $rel = Get-Candidate $tok $base
        if ($rel -and -not $out.Contains($rel)) { $out.Add($rel) }
        continue
      }
      if ($tok.StartsWith('-')) {
        if ($tok -eq '-e' -or $tok -eq '--regexp') { $sawPat = $true; $skipNext = $true }
        elseif ($tok -eq '-f' -or $tok -eq '--file') { $sawPat = $true; $pend = 'r' }
        elseif ($tok -match '^--(regexp|file)=') { $sawPat = $true }
        elseif ($exe -eq 'sed' -and $tok -match '^-[A-Za-z]*i') { $noRead = $true }
        continue
      }
      if ($skipNext) { $skipNext = $false; continue }
      $nop++
      if ($noRead) { continue }
      if (($scriptFirst -contains $exe) -and -not $sawPat -and $nop -eq 1) { continue }
      $rel = Get-Candidate $tok $base
      if ($rel -and -not $out.Contains($rel)) { $out.Add($rel) }
    }
  }
  return $out
}

function Get-Candidate([string]$Tok, [string]$Base) {
  if (-not $Tok) { return '' }
  if ($Tok -match '^[A-Za-z_][A-Za-z0-9_]*=') { return '' }
  if ($Tok.Contains('$')) { return '' }
  if ($Tok -match '^[0-9]+$') { return '' }
  return (Resolve-ProjectRelative $Tok $Base)
}

# Silent and append-only. Never writes to stdout: this runs on every Bash call.
function Invoke-Signal {
  if ($env:CONTEXT_KIT_NO_SIGNALS -eq '1') { exit 0 }
  $cmd = Get-JsonField 'tool_input.command'
  if (-not $cmd) { exit 0 }
  $sig = Get-CommandSignature $cmd
  if (-not $sig) { exit 0 }
  # Bare interpreters are listed without a compound form on purpose:
  # 'python3' alone is a throwaway script, 'python3 manage.py' is a procedure.
  $stop = @('ls','cd','cat','echo','pwd','which','head','tail','grep','find','mkdir','rm','cp','mv','sed','awk','wc','true','exit','git-status','git-diff','git-log',
            'diff','sort','uniq','cut','tr','touch','chmod','set','export','unset','printf','test','basename','dirname','date','od','xxd',
            'sh','bash','zsh','node','python','python3','perl','ruby')
  $firstWord = ($sig -split '-')[0]
  if ($stop -contains $sig -or $stop -contains $firstWord) { exit 0 }

  $sigDir = Join-Path $Data 'signals'
  if (-not (Test-Path $sigDir)) { New-Item -ItemType Directory -Force -Path $sigDir | Out-Null }
  $sigFile = Join-Path $sigDir "$Hash.tsv"
  $stamp = [int][double]::Parse((Get-Date -UFormat %s))
  Add-Content -Path $sigFile -Value "$sig`t$stamp"

  $lines = @(Get-Content $sigFile)
  if ($lines.Count -gt 1000) {
    Set-Content -Path $sigFile -Value ($lines | Select-Object -Last 500)
  }
  exit 0
}

# Who touched what. Silent, append-only, TSV: ts, kind, actor, target.
#
# This is the only record of the part of a session that leaves no artifact -
# which subagent was spawned for what, which files it read, which skills
# fired. /context-graph renders it as the activity layer over the static
# context layout; without it the graph shows the shelf and not the traffic.
#
# Records identifiers only - a tool name, a file path, a skill name, a
# subagent type. Never arguments, never file contents, never prompt text.
function Invoke-Event {
  if ($env:CONTEXT_KIT_NO_SIGNALS -eq '1') { exit 0 }
  if ($env:CONTEXT_KIT_NO_ACTIVITY -eq '1') { exit 0 }
  $obj = Get-HookInput
  if (-not $obj) { exit 0 }

  $sid = [string]$obj.session_id
  if (-not $sid) { $sid = 'session' }
  $actor = ($sid -replace '[^A-Za-z0-9]+', '-').Trim('-')
  if ($actor.Length -gt 16) { $actor = $actor.Substring(0, 16) }
  if (-not $actor) { $actor = 'session' }

  $evt = [string]$obj.hook_event_name
  $tool = [string]$obj.tool_name
  $kind = ''
  $target = ''

  if ($evt -eq 'SubagentStart' -or $evt -eq 'SubagentStop') {
    $kind = 'agent'
    $target = [string]$obj.subagent_type
    if (-not $target) { $target = [string]$obj.agent_type }
    if (-not $target) { $target = 'subagent' }
  } else {
    switch ($tool) {
      'Read'         { $kind = 'read';  $target = [string]$obj.tool_input.file_path }
      'NotebookRead' { $kind = 'read';  $target = [string]$obj.tool_input.file_path }
      'Edit'         { $kind = 'write'; $target = [string]$obj.tool_input.file_path }
      'Write'        { $kind = 'write'; $target = [string]$obj.tool_input.file_path }
      'NotebookEdit' { $kind = 'write'; $target = [string]$obj.tool_input.file_path }
      'Skill'        { $kind = 'skill'; $target = [string]$obj.tool_input.skill }
      'Task'         {
        $kind = 'agent'
        $target = [string]$obj.tool_input.subagent_type
        if (-not $target) { $target = 'subagent' }
      }
      'Bash'         {
        # One command can read several files, so this arm records its own
        # events and returns. Test-Path is what rejects the tokens
        # Get-ReadPaths could not rule out, like a sed script.
        $cmd = [string]$obj.tool_input.command
        if (-not $cmd) { exit 0 }
        $n = 0
        foreach ($rel in (Get-ReadPaths $cmd)) {
          if ($n -ge 40) { break }
          $full = Join-Path $Proj $rel
          if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
          Add-LedgerEvent 'read' $actor $rel
          $n++
        }
        Compress-Ledger
        exit 0
      }
      default { exit 0 }
    }
  }
  if (-not $target) { exit 0 }

  # Paths are stored project-relative so the ledger stays portable and no
  # machine-specific prefix reaches the graph or the vault. The guard also
  # rejects anything that resolves outside the project.
  if ($kind -eq 'read' -or $kind -eq 'write') {
    $target = Resolve-ProjectRelative $target ''
    if (-not $target) { exit 0 }
  }

  Add-LedgerEvent $kind $actor $target
  Compress-Ledger
  exit 0
}

function Get-LedgerPath {
  $evDir = Join-Path $Data 'events'
  if (-not (Test-Path $evDir)) { New-Item -ItemType Directory -Force -Path $evDir | Out-Null }
  return (Join-Path $evDir "$Hash.tsv")
}

function Add-LedgerEvent([string]$Kind, [string]$Actor, [string]$Target) {
  # A tab or newline in a value would desynchronize every later column.
  $t = ($Target -replace "[`t`r`n]", ' ').Trim()
  if ($t.Length -gt 200) { $t = $t.Substring(0, 200) }
  if (-not $t) { return }
  $stamp = [int][double]::Parse((Get-Date -UFormat %s))
  Add-Content -Path (Get-LedgerPath) -Value "$stamp`t$Kind`t$Actor`t$t"
}

# Trim reads first and keep agent and skill events: the graph reads "never
# invoked in the recorded activity" off whatever survived, so a burst of
# reads evicting the skill rows would manufacture that finding.
function Compress-Ledger {
  $evFile = Get-LedgerPath
  if (-not (Test-Path $evFile)) { return }
  $lines = @(Get-Content $evFile)
  if ($lines.Count -le 4000) { return }
  $keep = @($lines | Where-Object { $_ -match "^[^`t]*`t(agent|skill)`t" } | Select-Object -Last 1000)
  $rest = @($lines | Where-Object { $_ -notmatch "^[^`t]*`t(agent|skill)`t" } | Select-Object -Last 2000)
  $merged = @($keep + $rest) | Sort-Object { [int](($_ -split "`t")[0]) }
  Set-Content -Path $evFile -Value $merged
}

switch ($Action) {
  'session'  { Invoke-Session }
  'subagent' { Invoke-Subagent }
  'mode'     { Invoke-Mode }
  'signal'   { Invoke-Signal }
  'event'    { Invoke-Event }
  default    { exit 0 }
}
exit 0
