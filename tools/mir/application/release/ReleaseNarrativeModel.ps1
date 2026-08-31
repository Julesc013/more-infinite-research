Set-StrictMode -Version Latest

$script:MIR4NarrativeAbi = 'mir4-release-narratives/1'
$script:MIR4NarrativeTargets = @('F210', 'F200', 'F110', 'F100')
$script:MIR4NarrativeRedaction = 'Security correction details withheld pending coordinated disclosure.'

function Read-MIR4NarrativeJsonV1 {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$SchemaPath)
  $full = Join-Path $RepoRoot $Path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-release-narrative-input-missing] $Path" }
  $text = [IO.File]::ReadAllText($full)
  if (-not ($text | Test-Json -SchemaFile (Join-Path $RepoRoot $SchemaPath))) { throw "[mir4-release-narrative-schema] $Path" }
  return $text | ConvertFrom-Json -Depth 100 -DateKind String
}

function Get-MIR4NarrativeFileIdentityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$Path)
  $full = Join-Path $RepoRoot $Path
  return [ordered]@{path=$Path.Replace('\\','/');sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()}
}

function Assert-MIR4NarrativeFragmentV1 {
  param([Parameter(Mandatory)]$Fragment)
  if ([string]$Fragment.status -notin @('accepted','released')) { throw "[mir4-release-narrative-change-not-accepted] $($Fragment.change_id)" }
  $rows = @($Fragment.target_dispositions)
  if ($rows.Count -ne 4 -or @($rows.target | Sort-Object -Unique).Count -ne 4) { throw "[mir4-release-narrative-target-closure] $($Fragment.change_id)" }
  for ($i = 0; $i -lt $script:MIR4NarrativeTargets.Count; $i++) {
    if ([string]$rows[$i].target -cne $script:MIR4NarrativeTargets[$i]) { throw "[mir4-release-narrative-target-order] $($Fragment.change_id)" }
  }
  if (@($rows | Where-Object disposition -eq 'unknown').Count -ne 0) { throw "[mir4-release-narrative-unknown-target] $($Fragment.change_id)" }
  foreach ($impact in $Fragment.impacts.PSObject.Properties) {
    if ([string]$impact.Value -ceq 'unknown') { throw "[mir4-release-narrative-unknown-impact] $($Fragment.change_id):$($impact.Name)" }
  }
}

function Get-MIR4NarrativeDispositionV1 {
  param([Parameter(Mandatory)]$Fragment, [Parameter(Mandatory)][string]$Surface)
  return [string]$Fragment.release_surfaces.$Surface
}

function Get-MIR4NarrativeSummaryV1 {
  param([Parameter(Mandatory)]$Fragment, [Parameter(Mandatory)][string]$Surface)
  $disposition = Get-MIR4NarrativeDispositionV1 -Fragment $Fragment -Surface $Surface
  if ($disposition -ceq 'redact') { return $script:MIR4NarrativeRedaction }
  return [string]$Fragment.summary
}

function Get-MIR4NarrativeSurfaceChangesV1 {
  param([Parameter(Mandatory)][object[]]$Fragments, [Parameter(Mandatory)][string]$Surface, [string]$Target = '')
  $selected = foreach ($fragment in $Fragments) {
    $surfaceDisposition = Get-MIR4NarrativeDispositionV1 -Fragment $fragment -Surface $Surface
    if ($surfaceDisposition -ceq 'omit') { continue }
    if ($Target) {
      $targetRow = @($fragment.target_dispositions | Where-Object target -eq $Target)
      if ($targetRow.Count -ne 1 -or [string]$targetRow[0].disposition -cne 'affected') { continue }
    }
    $fragment
  }
  return @($selected)
}

function Get-MIR4NarrativeCategoryV1 {
  param([Parameter(Mandatory)][string]$ChangeType)
  switch ($ChangeType) {
    'added' { 'Features' } 'fixed' { 'Bugfixes' } 'security' { 'Security' }
    'deprecated' { 'Deprecated' } 'removed' { 'Removed' } default { 'Changes' }
  }
}

function ConvertTo-MIR4NarrativeLinesV1 {
  param([Parameter(Mandatory)][object[]]$Fragments, [Parameter(Mandatory)][string]$Surface)
  $lines = [Collections.Generic.List[string]]::new()
  foreach ($group in @($Fragments | Group-Object { Get-MIR4NarrativeCategoryV1 ([string]$_.change_type) } | Sort-Object Name)) {
    $lines.Add("### $($group.Name)")
    $lines.Add('')
    foreach ($fragment in @($group.Group | Sort-Object change_id)) {
      $lines.Add("- $(Get-MIR4NarrativeSummaryV1 -Fragment $fragment -Surface $Surface) [$([string]$fragment.change_id)]")
      if ((Get-MIR4NarrativeDispositionV1 -Fragment $fragment -Surface $Surface) -ceq 'include') {
        foreach ($detail in @($fragment.details)) { $lines.Add("  - $detail") }
      }
    }
    $lines.Add('')
  }
  return @($lines)
}

function Assert-MIR4NarrativePublicCopyV1 {
  param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Surface, [Parameter(Mandatory)][string]$ReleaseKind)
  if ($Surface -ceq 'github' -and $Text -match '(?m)^# ') { throw '[mir4-release-narrative-github-h1]' }
  foreach ($pattern in @('(?i)\bTBD\b','(?i)\bplaceholder\b','(?i)whole-platform genesis','(?i)candidate ceremony','(?i)\bCodex\b','(?i)\bChatGPT\b','[A-Za-z]:\\\\','(?m)^##[^\r\n]+\r?\n\r?\n(?=##)')) {
    if ($Text -match $pattern) { throw "[mir4-release-narrative-public-copy] ${Surface}:$pattern" }
  }
  $words = @($Text -split '\s+' | Where-Object { $_ }).Count
  $bounds = @{hotfix=@(100,200);patch=@(150,350);minor=@(300,800);major=@(500,1200);beta=@(200,500);rc=@(200,500);historical=@(1,1200)}
  $bound = $bounds[$ReleaseKind]
  if ($words -lt $bound[0] -or $words -gt $bound[1]) { throw "[mir4-release-narrative-size-budget] ${Surface}:${ReleaseKind}:$words" }
}

function Assert-MIR4FactorioChangelogV1 {
  param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Version)
  $separator = '-' * 99
  if ($Text -notmatch "(?m)^$([regex]::Escape($separator))$") { throw '[mir4-release-narrative-factorio-separator]' }
  if ($Text -notmatch "(?m)^Version: $([regex]::Escape($Version))$" -or $Version -notmatch '^\d+\.\d+\.\d+$') { throw '[mir4-release-narrative-factorio-version]' }
  if ($Text.Contains("`t") -or $Text -notmatch '(?m)^  (Features|Changes|Bugfixes|Security|Deprecated|Removed):$' -or $Text -notmatch '(?m)^    - ') { throw '[mir4-release-narrative-factorio-format]' }
}
