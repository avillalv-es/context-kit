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

function Get-JsonField([string]$Name) {
  $obj = Get-HookInput
  if (-not $obj) { return '' }
  try {
    if ($Name -eq 'command') { return [string]$obj.tool_input.command }
    return [string]$obj.$Name
  } catch { return '' }
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
  if ($level -eq 'off') { exit 0 }
  $notes = @()

  # Bootstrap: offer once per project, then never nag. Repeating it every
  # session start turns a helpful hint into a nag.
  $offered = Join-Path $Data "state\$Hash.offered"
  if (-not (Test-Path $offered)) {
    $claudeMd = Join-Path $Proj 'CLAUDE.md'
    $hasMarker = (Test-Path $claudeMd) -and ((Get-Content $claudeMd) -match '^## Context layout')
    if (-not $hasMarker) {
      $notes += 'context-kit: this project has no context layout yet. Use the context-cleanup skill in Mode 0 now - it scaffolds the layout and creates or appends the CLAUDE.md block - then carry on with whatever was asked.'
      $stateDir = Join-Path $Data 'state'
      if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force -Path $stateDir | Out-Null }
      New-Item -ItemType File -Force -Path $offered | Out-Null
    }
  }

  $repeats = Get-PendingRepeats
  if ($repeats) {
    $notes += "context-kit: these procedures repeated $Threshold+ times and no skill covers them: $repeats. Capture the genuinely repeatable ones with the skill-capture skill."
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
  $text = ($text -split '[|;&]')[0].Trim()
  if (-not $text) { return '' }

  $tokens = @($text -split '\s+' | Where-Object { $_ })
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
  if ($i -ge $tokens.Count) { return '' }

  $exe = ((($tokens[$i]) -replace '.*[\\/]', '') -replace '\.exe$', '').ToLower()
  $arg = ''
  if ($i + 1 -lt $tokens.Count) {
    $nxt = $tokens[$i + 1]
    # A subcommand, and only a subcommand: a flag value or a path would give
    # every invocation its own signature.
    if ($nxt -and -not $nxt.StartsWith('-') -and $nxt -notmatch '[/=\\]') { $arg = $nxt.ToLower() }
  }
  $sig = if ($arg) { "$exe-$arg" } else { $exe }
  return ($sig -replace '[^a-z0-9]+', '-').Trim('-')
}

# Silent and append-only. Never writes to stdout: this runs on every Bash call.
function Invoke-Signal {
  if ($env:CONTEXT_KIT_NO_SIGNALS -eq '1') { exit 0 }
  $cmd = Get-JsonField 'command'
  if (-not $cmd) { exit 0 }
  $sig = Get-CommandSignature $cmd
  if (-not $sig) { exit 0 }
  $stop = @('ls','cd','cat','echo','pwd','which','head','tail','grep','find','mkdir','rm','cp','mv','sed','awk','wc','true','exit','git-status','git-diff','git-log')
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
      default { exit 0 }
    }
  }
  if (-not $target) { exit 0 }

  # Paths are stored project-relative so the ledger stays portable and no
  # machine-specific prefix reaches the graph or the vault.
  if ($kind -eq 'read' -or $kind -eq 'write') {
    $normTarget = $target -replace '\\', '/'
    $normProj = ($Proj -replace '\\', '/').TrimEnd('/')
    if ($normTarget.StartsWith($normProj + '/', [StringComparison]::OrdinalIgnoreCase)) {
      $target = $normTarget.Substring($normProj.Length + 1)
    } elseif ($normTarget -match '^([A-Za-z]:)?/') {
      exit 0  # outside the project: not ours to record
    } else {
      $target = $normTarget
    }
  }

  # A tab or newline in a value would desynchronize every later column.
  $target = ($target -replace "[`t`r`n]", ' ').Trim()
  if ($target.Length -gt 200) { $target = $target.Substring(0, 200) }
  if (-not $target) { exit 0 }

  $evDir = Join-Path $Data 'events'
  if (-not (Test-Path $evDir)) { New-Item -ItemType Directory -Force -Path $evDir | Out-Null }
  $evFile = Join-Path $evDir "$Hash.tsv"
  $stamp = [int][double]::Parse((Get-Date -UFormat %s))
  Add-Content -Path $evFile -Value "$stamp`t$kind`t$actor`t$target"

  $lines = @(Get-Content $evFile)
  if ($lines.Count -gt 4000) {
    Set-Content -Path $evFile -Value ($lines | Select-Object -Last 2000)
  }
  exit 0
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
