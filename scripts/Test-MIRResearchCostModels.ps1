param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }

function Get-CanonicalFormula {
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

function Get-Cost {
  param([int]$Level, [int]$Anchor, [double]$Base, [int]$Increment, [double]$Growth)
  $offset = $Level - $Anchor
  return ($Base + $Increment * $offset) * [Math]::Pow($Growth, $offset)
}

$cases = @(
  @{ Kind = "fixed"; Anchor = 4; Base = 1000; Increment = 0; Growth = 1; Formula = "1000" },
  @{ Kind = "linear"; Anchor = 4; Base = 1000; Increment = 250; Growth = 1; Formula = "1000+250*(L-4)" },
  @{ Kind = "exponential"; Anchor = 4; Base = 1000; Increment = 0; Growth = 1.5; Formula = "1000*1.5^(L-4)" },
  @{ Kind = "hybrid"; Anchor = 4; Base = 1000; Increment = 250; Growth = 1.5; Formula = "(1000+250*(L-4))*1.5^(L-4)" }
)

foreach ($case in $cases) {
  $actual = Get-CanonicalFormula -Anchor $case.Anchor -Base $case.Base -Increment $case.Increment -Growth $case.Growth
  if ($actual -ne $case.Formula) { throw "$($case.Kind) canonical formula drifted: $actual" }
  $previous = 0.0
  foreach ($level in $case.Anchor..($case.Anchor + 20)) {
    $cost = Get-Cost -Level $level -Anchor $case.Anchor -Base $case.Base -Increment $case.Increment -Growth $case.Growth
    if ($cost -le 0 -or $cost -lt $previous) { throw "$($case.Kind) cost is not positive and nondecreasing at level $level." }
    $previous = $cost
  }
}

foreach ($invalid in @(
  @{ Anchor = 0; Base = 1000; Increment = 0; Growth = 1 },
  @{ Anchor = 1; Base = 0; Increment = 0; Growth = 1 },
  @{ Anchor = 1; Base = 1000; Increment = -1; Growth = 1 },
  @{ Anchor = 1; Base = 1000; Increment = 0; Growth = 0.99 }
)) {
  $rejected = $false
  try { Get-CanonicalFormula @invalid | Out-Null } catch { $rejected = $true }
  if (-not $rejected) { throw "Unsafe research-cost parameter set was accepted." }
}

$paths = @{
  Contract = "prototypes/mir/settings/cost_contract.lua"
  Model = "prototypes/mir/domain/research_cost/model.lua"
  Formula = "prototypes/mir/domain/research_cost/formula.lua"
  Validation = "prototypes/mir/domain/research_cost/validation.lua"
  Classification = "prototypes/mir/domain/research_cost/classification.lua"
  Projection = "prototypes/mir/domain/research_cost/projection.lua"
  Streams = "prototypes/mir/planner/stream_compiler.lua"
  NativeCost = "prototypes/mir/domain/native_owner/cost_model.lua"
  Native = "prototypes/mir/planner/native_owner_binding.lua"
  Continuations = "prototypes/mir/planner/base_continuations.lua"
}
$source = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $path = Join-Path $RepoRoot $entry.Value
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing research-cost module: $($entry.Value)" }
  $source[$entry.Key] = Get-Content -Raw -LiteralPath $path
}

foreach ($required in @("ips-cost-linear-increment-%s", "mir-cost-linear-increment-%s", "mir-research-cost-v1")) {
  if (($source.Values -join "`n") -notmatch [regex]::Escape($required)) { throw "Missing research-cost contract token: $required" }
}
if ($source.Contract -match 'mode%-setting|dropdown') { throw "Research-cost contract must not expose a model dropdown." }
if ($source.Classification -notmatch 'original_formula' -or $source.NativeCost -notmatch 'changed = false') {
  throw "Unchanged external formula preservation contract is missing."
}
if ($source.NativeCost -match 'fixed_count_has_no_(growth_factor|linear_increment)' -or
    $source.NativeCost -notmatch 'configured\.derived_kind\s*==\s*"fixed"') {
  throw "Fixed-count native owners must project through the same fixed/linear/exponential/hybrid controls."
}
foreach ($route in @("Streams", "Native", "Continuations")) {
  if ($source[$route] -notmatch 'research_cost') { throw "$route does not consume the unified research-cost model." }
}

$defaults = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes/mir/settings/defaults.lua")
if ($defaults -notmatch 'linear_increment\s*=\s*0') { throw "Default linear increment must remain zero." }
$unknownFixture = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures/native-owner-unrecognized-formula/data-updates.lua")
if ($unknownFixture -notmatch 'L\^2') { throw "Unknown-formula fixture must remain outside the supported fixed/linear/exponential/hybrid family." }

Write-Host "[ok] unified fixed, linear, exponential, and hybrid ResearchCostModel contract passed."
