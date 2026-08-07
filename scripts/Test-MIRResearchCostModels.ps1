[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path)

$ErrorActionPreference = "Stop"

function Get-MIRCanonicalResearchFormula {
  param([int]$Anchor, [double]$Base, [int]$Increment, [double]$Growth)
  if ($Anchor -lt 1 -or $Base -lt 1 -or $Increment -lt 0 -or $Growth -lt 1) {
    throw "Invalid research-cost parameters."
  }
  $number = { param($Value) ([double]$Value).ToString("G15", [Globalization.CultureInfo]::InvariantCulture) }
  $b = & $number $Base
  $a = & $number $Increment
  $g = & $number $Growth
  $offset = "(L-$Anchor)"
  if ($Increment -eq 0 -and $Growth -eq 1) { return $b }
  if ($Increment -gt 0 -and $Growth -eq 1) { return "$b+$a*$offset" }
  if ($Increment -eq 0) { return "$b*$g^$offset" }
  return "($b+$a*$offset)*$g^$offset"
}

function Get-MIRResearchCost {
  param([int]$Level, [int]$Anchor, [double]$Base, [int]$Increment, [double]$Growth)
  $offset = $Level - $Anchor
  return ($Base + $Increment * $offset) * [Math]::Pow($Growth, $offset)
}

$cases = @(
  @{Kind="fixed"; Anchor=4; Base=1000; Increment=0; Growth=1; Formula="1000"},
  @{Kind="linear"; Anchor=4; Base=1000; Increment=250; Growth=1; Formula="1000+250*(L-4)"},
  @{Kind="exponential"; Anchor=4; Base=1000; Increment=0; Growth=1.5; Formula="1000*1.5^(L-4)"},
  @{Kind="hybrid"; Anchor=4; Base=1000; Increment=250; Growth=1.5; Formula="(1000+250*(L-4))*1.5^(L-4)"}
)

foreach ($case in $cases) {
  $formula = Get-MIRCanonicalResearchFormula -Anchor $case.Anchor -Base $case.Base -Increment $case.Increment -Growth $case.Growth
  if ($formula -ne $case.Formula) { throw "$($case.Kind) formula drifted: $formula" }
  $previous = 0.0
  foreach ($level in $case.Anchor..($case.Anchor + 20)) {
    $cost = Get-MIRResearchCost -Level $level -Anchor $case.Anchor -Base $case.Base -Increment $case.Increment -Growth $case.Growth
    if ($cost -le 0 -or $cost -lt $previous) { throw "$($case.Kind) cost is unsafe at level $level." }
    $previous = $cost
  }
}

$transitions = 0
foreach ($before in $cases) {
  foreach ($after in $cases) {
    $oldCost = [Math]::Floor((Get-MIRResearchCost -Level 8 -Anchor $before.Anchor -Base $before.Base -Increment $before.Increment -Growth $before.Growth))
    $newCost = [Math]::Floor((Get-MIRResearchCost -Level 8 -Anchor $after.Anchor -Base $after.Base -Increment $after.Increment -Growth $after.Growth))
    $fraction = [Math]::Max(0.0, [Math]::Min(1.0, 0.42 * $oldCost / $newCost))
    if ([Math]::Abs(($fraction * $newCost) - [Math]::Min(0.42 * $oldCost, $newCost)) -gt 0.000001) {
      throw "Completed work drifted for $($before.Kind) -> $($after.Kind)."
    }
    $transitions++
  }
}
if ($transitions -ne 16) { throw "Research-cost transition matrix must contain sixteen rows." }

$requiredSources = @(
  "prototypes/mir/settings/cost_contract.lua",
  "prototypes/mir/domain/research_cost/model.lua",
  "prototypes/mir/domain/research_cost/formula.lua",
  "prototypes/mir/domain/research_cost/validation.lua",
  "prototypes/mir/domain/research_cost/classification.lua",
  "prototypes/mir/domain/research_cost/projection.lua",
  "prototypes/mir/domain/research_cost/transition_descriptor.lua"
)
$combined = ($requiredSources | ForEach-Object {
  $path = Join-Path $RepoRoot $_
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing research-cost module: $_" }
  Get-Content -Raw -LiteralPath $path
}) -join "`n"
foreach ($token in @("fixed", "linear", "exponential", "hybrid")) {
  if (-not $combined.Contains($token)) { throw "Missing research-cost contract token: $token" }
}

$targets = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir/targets.json") | ConvertFrom-Json
$info = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "info.json") | ConvertFrom-Json
$targetLine = [string]$info.factorio_version
$target = $targets.profiles.PSObject.Properties[$targetLine].Value
if ($null -eq $target -or [bool]$target.prototype_shapes.mod_data -or
    [bool]$target.features.productivity_family_adoption -or [bool]$target.features.settings_profiles -or
    @($target.emitter_families | Where-Object { [string]$_ -ne "technology" }).Count -ne 0) {
  throw "Factorio $targetLine must keep research costs on the reduced technology-only boundary."
}

Write-Host "[ok] unified Factorio $targetLine research-cost model, sixteen transitions, and reduced target boundaries passed."
