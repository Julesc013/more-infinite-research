# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
)

$ErrorActionPreference = 'Stop'

function Assert-MIR4MaterialStreamAuthority {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw $Code }
}

function Get-MIR4StreamRecordBlock {
  param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Id)
  $escaped = [regex]::Escape($Id)
  $match = [regex]::Match($Text, "(?ms)^    $escaped`:\r?\n(?<body>.*?)(?=^    [A-Za-z0-9._-]+`:\r?\n|\z)")
  Assert-MIR4MaterialStreamAuthority $match.Success "[mir4-m42-stream-authority-record-missing] $Id"
  return $match.Value
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$sourceManifestPath = Join-Path $repo 'source/prototypes/mir/streams/generated_stream_manifest.json'
$authorityPath = Join-Path $repo '.mir/streams.yml'
$f110ProfilePath = Join-Path $repo 'source/adapters/f110/prototypes/mir/platform/factorio/target_profiles.lua'
$f100ProfilePath = Join-Path $repo 'source/adapters/f100/prototypes/mir/platform/factorio/target_profiles.lua'

foreach ($path in @($sourceManifestPath, $authorityPath, $f110ProfilePath, $f100ProfilePath)) {
  Assert-MIR4MaterialStreamAuthority (Test-Path -LiteralPath $path -PathType Leaf) "[mir4-m42-stream-authority-input-missing] $path"
}

$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json -Depth 30 -DateKind String
$authorityText = Get-Content -Raw -LiteralPath $authorityPath
$sourceRows = @($sourceManifest.streams.PSObject.Properties)
$authorityRows = @([regex]::Matches($authorityText, '(?m)^    ([A-Za-z0-9._-]+):\s*$') | ForEach-Object { $_.Groups[1].Value })
Assert-MIR4MaterialStreamAuthority ($sourceRows.Count -eq 98) '[mir4-m42-stream-authority-source-count]'
Assert-MIR4MaterialStreamAuthority ($authorityRows.Count -eq 98) '[mir4-m42-stream-authority-canonical-count]'
Assert-MIR4MaterialStreamAuthority (@($authorityRows | Sort-Object -Unique).Count -eq 98) '[mir4-m42-stream-authority-canonical-duplicate]'

foreach ($sourceRow in $sourceRows) {
  $id = [string]$sourceRow.Name
  $record = Get-MIR4StreamRecordBlock -Text $authorityText -Id $id
  Assert-MIR4MaterialStreamAuthority ($record.Contains("canonical_row: prototypes/mir/streams/generated_stream_manifest.json#streams.$id")) "[mir4-m42-stream-authority-canonical-row] $id"
  foreach ($field in @('introduced_in', 'source', 'capability', 'family', 'policy', 'generated_technology', 'stream_key', 'migration_policy')) {
    $value = [string]$sourceRow.Value.$field
    $escapedField = [regex]::Escape($field)
    $escapedValue = [regex]::Escape($value)
    Assert-MIR4MaterialStreamAuthority ([regex]::IsMatch($record, "(?m)^      $escapedField`: ?`"?$escapedValue`"?\s*$")) "[mir4-m42-stream-authority-field] $id/$field"
  }
}

$materialRows = @($sourceRows | Where-Object { [string]$_.Name -like 'recipe-prod-research_material_*' })
Assert-MIR4MaterialStreamAuthority ($materialRows.Count -eq 22) '[mir4-m42-stream-authority-material-count]'
foreach ($sourceRow in $materialRows) {
  $id = [string]$sourceRow.Name
  $source = $sourceRow.Value
  $record = Get-MIR4StreamRecordBlock -Text $authorityText -Id $id
  Assert-MIR4MaterialStreamAuthority ([string]$source.identity_state -ceq 'stable-unreleased') "[mir4-m42-stream-authority-identity-source] $id"
  Assert-MIR4MaterialStreamAuthority ($record -match '(?m)^      identity_state: stable-unreleased\s*$') "[mir4-m42-stream-authority-identity-canonical] $id"
  Assert-MIR4MaterialStreamAuthority ([string]$source.migration_policy -ceq 'stable') "[mir4-m42-stream-authority-migration-source] $id"
  Assert-MIR4MaterialStreamAuthority ($record -match '(?m)^      migration_policy: stable\s*$') "[mir4-m42-stream-authority-migration-canonical] $id"
  Assert-MIR4MaterialStreamAuthority ($record -match '(?ms)^      target_capability_disposition:\r?\n        f110: omitted-recipe-productivity-unavailable\r?\n        f100: omitted-recipe-productivity-unavailable\s*$') "[mir4-m42-stream-authority-f1-disposition] $id"
}

$acyclic = @($materialRows | Where-Object { [string]$_.Value.policy -ceq 'exact-acyclic-material-manufacturing' })
$reviewedForward = @($materialRows | Where-Object { [string]$_.Value.policy -ceq 'exact-reviewed-forward-material-manufacturing' })
Assert-MIR4MaterialStreamAuthority ($acyclic.Count -eq 19) '[mir4-m42-stream-authority-acyclic-count]'
Assert-MIR4MaterialStreamAuthority ((@($reviewedForward.Value.stream_key | Sort-Object) -join '|') -ceq 'research_material_glass|research_material_rare_metals|research_material_silicon') '[mir4-m42-stream-authority-reviewed-forward-set]'

foreach ($profilePath in @($f110ProfilePath, $f100ProfilePath)) {
  $profile = Get-Content -Raw -LiteralPath $profilePath
  Assert-MIR4MaterialStreamAuthority ($profile -match '(?ms)features\s*=\s*\{.*?recipe_productivity\s*=\s*false') "[mir4-m42-stream-authority-f1-capability] $profilePath"
}

Write-Host '[ok] MIR 4.2 material stream authority reconciles all 98 emitted streams and explicitly omits the 22 recipe-productivity rows on F110/F100.'
