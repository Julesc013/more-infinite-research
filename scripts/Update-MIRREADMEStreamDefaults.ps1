param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")),
  [switch]$Check
)

$ErrorActionPreference = "Stop"

$defaultsPath = Join-Path $RepoRoot "prototypes\mir\settings\defaults.lua"
$readmePath = Join-Path $RepoRoot "README.md"
$defaultsText = Get-Content -Raw -LiteralPath $defaultsPath
$readmeText = Get-Content -Raw -LiteralPath $readmePath

function Get-MIRLuaScalar {
  param(
    [Parameter(Mandatory)][string]$Body,
    [Parameter(Mandatory)][string]$Name
  )

  $pattern = '(?m)^[ \t]+' + [regex]::Escape($Name) + '[ \t]*=[ \t]*(?<value>true|false|-?\d+(?:\.\d+)?)[ \t]*,?[ \t]*(?:--.*)?\r?$'
  $match = [regex]::Match($Body, $pattern)
  if (-not $match.Success) { return $null }
  return $match.Groups["value"].Value
}

$sharedMatch = [regex]::Match($defaultsText, '(?ms)^  shared = \{\r?\n(?<body>.*?)^  \},')
if (-not $sharedMatch.Success) { throw "Could not parse defaults.shared from $defaultsPath" }
$sharedBody = $sharedMatch.Groups["body"].Value
$fieldNames = @("enabled", "base_cost", "growth_factor", "research_time", "max_level")
$shared = [ordered]@{}
foreach ($fieldName in $fieldNames) {
  $value = Get-MIRLuaScalar -Body $sharedBody -Name $fieldName
  if ($null -eq $value) { throw "defaults.shared.$fieldName is missing or not a supported scalar." }
  $shared[$fieldName] = $value
}

$streamPattern = '(?ms)^    (?<key>research_[A-Za-z0-9_]+) = \{(?:\r?\n(?<body_multiline>.*?)^    \}|(?<body_single>[^\r\n{}]*)\})[ \t]*,?[ \t]*\r?$'
$streamMatches = [regex]::Matches($defaultsText, $streamPattern)
if ($streamMatches.Count -eq 0) { throw "Could not parse defaults.streams from $defaultsPath" }

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($match in $streamMatches) {
  $body = if ($match.Groups["body_multiline"].Success) {
    $match.Groups["body_multiline"].Value
  } else {
    $match.Groups["body_single"].Value
  }
  $values = [ordered]@{}
  $hasUserFacingOverride = $false
  foreach ($fieldName in $fieldNames) {
    $explicit = Get-MIRLuaScalar -Body $body -Name $fieldName
    if ($null -ne $explicit) {
      $values[$fieldName] = $explicit
      $hasUserFacingOverride = $true
    } else {
      $values[$fieldName] = $shared[$fieldName]
    }
  }

  $isAttentionRow = $body -match '(?m)^[ \t]+settings_priority[ \t]*=[ \t]*"top"[ \t]*,?[ \t]*\r?$'
  if ($hasUserFacingOverride -or $isAttentionRow) {
    $rows.Add([pscustomobject]@{
      key = $match.Groups["key"].Value
      enabled = $values.enabled
      base_cost = $values.base_cost
      growth_factor = $values.growth_factor
      research_time = $values.research_time
      max_level = $values.max_level
    })
  }
}

function Format-MIREnabled {
  param([Parameter(Mandatory)][string]$Value)
  if ($Value -eq "true") { return "Yes" }
  if ($Value -eq "false") { return "No" }
  throw "Unsupported Lua boolean: $Value"
}

function Format-MIRMaximum {
  param([Parameter(Mandatory)][string]$Value)
  if ($Value -eq "0") { return "Infinite" }
  return "``$Value``"
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('<!-- BEGIN GENERATED MIR STREAM DEFAULTS -->')
$lines.Add('This effective-default table is generated from `prototypes/mir/settings/defaults.lua`; run `./scripts/Update-MIRREADMEStreamDefaults.ps1` after changing stream defaults. It includes every stream with an explicit user-facing default override or a top-priority settings row.')
$lines.Add('')
$lines.Add('| Stream | Enabled | Base cost | Growth | Time | Max |')
$lines.Add('| --- | --- | ---: | ---: | ---: | --- |')
$lines.Add("| Shared stream default | $(Format-MIREnabled -Value $shared.enabled) | ``$($shared.base_cost)`` | ``$($shared.growth_factor)`` | ``$($shared.research_time)`` | $(Format-MIRMaximum -Value $shared.max_level) |")
foreach ($row in $rows) {
  $lines.Add("| ``$($row.key)`` | $(Format-MIREnabled -Value $row.enabled) | ``$($row.base_cost)`` | ``$($row.growth_factor)`` | ``$($row.research_time)`` | $(Format-MIRMaximum -Value $row.max_level) |")
}
$lines.Add('<!-- END GENERATED MIR STREAM DEFAULTS -->')
$generated = $lines -join [Environment]::NewLine

$markerPattern = '(?s)<!-- BEGIN GENERATED MIR STREAM DEFAULTS -->.*?<!-- END GENERATED MIR STREAM DEFAULTS -->'
if (-not [regex]::IsMatch($readmeText, $markerPattern)) { throw "README stream-default markers are missing." }
$updated = [regex]::Replace(
  $readmeText,
  $markerPattern,
  [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $generated },
  1
)

if ($Check) {
  if ($updated -cne $readmeText) {
    throw "README stream-default table is stale; run scripts/Update-MIRREADMEStreamDefaults.ps1."
  }
  Write-Host "[ok] README effective stream defaults match defaults.lua."
  return
}

[System.IO.File]::WriteAllText($readmePath, $updated, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated $readmePath"
