param([string]$RepoRoot = "")
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $MirLegacyScriptRoot "..")).Path }

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

function Get-WorkPreservingFraction {
  param([double]$Fraction, [double]$PreviousCost, [double]$CurrentCost)
  if ($PreviousCost -lt 1 -or $CurrentCost -lt 1) { throw "Realized research costs must be positive." }
  return [Math]::Max(0.0, [Math]::Min(1.0, $Fraction * $PreviousCost / $CurrentCost))
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

$transitionRows = 0
foreach ($previous in $cases) {
  foreach ($current in $cases) {
    $previousCost = [Math]::Floor((Get-Cost -Level 8 -Anchor $previous.Anchor -Base $previous.Base -Increment $previous.Increment -Growth $previous.Growth))
    $currentCost = [Math]::Floor((Get-Cost -Level 8 -Anchor $current.Anchor -Base $current.Base -Increment $current.Increment -Growth $current.Growth))
    $actual = Get-WorkPreservingFraction -Fraction 0.42 -PreviousCost $previousCost -CurrentCost $currentCost
    $expectedWork = [Math]::Min(0.42 * $previousCost, $currentCost)
    if ([Math]::Abs(($actual * $currentCost) - $expectedWork) -gt 0.000001) {
      throw "Completed work drifted for $($previous.Kind) -> $($current.Kind)."
    }
    $transitionRows++
  }
}
if ($transitionRows -ne 16) { throw "Research-cost transition matrix must contain exactly sixteen rows." }

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
  Transition = "prototypes/mir/domain/research_cost/transition_descriptor.lua"
  AdoptionEmitter = "prototypes/mir/emit/transactions/productivity_family_adoption.lua"
  AdoptionRuntime = "prototypes/mir/runtime/productivity_family_adoption.lua"
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

foreach ($required in @("ips-cost-linear-increment-%s", "mir-cost-linear-increment-%s", "mir-research-cost-v1", "mir-research-cost-transition-v1", "mir-research-cost-qualification-v1")) {
  if (($source.Values -join "`n") -notmatch [regex]::Escape($required)) { throw "Missing research-cost contract token: $required" }
}
foreach ($digest in @("semantic_digest", "authority_digest", "qualification_digest")) {
  if ($source.Model -notmatch $digest -or $source.Transition -notmatch $digest) {
    throw "Research-cost identity layer is missing: $digest"
  }
}
if ($source.AdoptionEmitter -notmatch 'VERSION\s*=\s*3' -or
    $source.AdoptionEmitter -notmatch 'input_descriptor' -or $source.AdoptionEmitter -notmatch 'output_descriptor') {
  throw "Native-owner adoption does not emit versioned old/new research-cost descriptors."
}
if ($source.AdoptionRuntime -match 'count_formula.*match|research_unit_count|force\.research_progress\s*=' -or
    $source.AdoptionRuntime -notmatch 'no second conversion was applied' -or
    $source.AdoptionRuntime -notmatch 'transition_descriptor\.evaluate') {
  throw "Runtime must retain Factorio-normalized progress and may only evaluate canonical descriptors for diagnostics."
}
if ($source.Transition -notmatch 'before \* previous_cost / current_cost') {
  throw "Analytical research-progress conversion must preserve work with the old-cost/new-cost ratio."
}
foreach ($budget in @('MAXIMUM_FORMULA_BYTES', 'MAXIMUM_TOKENS', 'MAXIMUM_PARSE_DEPTH', 'evaluated_cost_out_of_bounds')) {
  if (($source.Values -join "`n") -notmatch $budget) { throw "Research-cost budget is missing: $budget" }
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
if ($source.Continuations -notmatch 'base_coefficient \* \(growth \^ \(desired_new_level - 1\)\)' -or
    $source.Continuations -notmatch 'legacy_formula_number\(base_coefficient\)' -or
    $source.Continuations -notmatch 'legacy_formula_number\(growth\)' -or
    $source.Continuations -notmatch 'legacy-six-digit-coefficient-projection:' -or
    $source.Continuations -notmatch 'legacy-six-digit-growth-projection:') {
  throw "Base continuations must preserve six-digit legacy operands and project the L=1 coefficient to the anchor."
}
$legacyInserterCoefficient = 200
$factorioEffectiveInserterGrowth = 3.33333
$inserterAnchorLevel = 8
$projectedInserterAnchorCost = $legacyInserterCoefficient *
  [Math]::Pow($factorioEffectiveInserterGrowth, $inserterAnchorLevel - 1)
if ([Math]::Floor($projectedInserterAnchorCost) -ne 914488) {
  throw "The 3.2.3 inserter continuation default did not project to its exact Factorio 2.1 anchor cost."
}
$projectedHybridNextCost = ($projectedInserterAnchorCost + 250) * $factorioEffectiveInserterGrowth
if ($projectedHybridNextCost -le $projectedInserterAnchorCost) {
  throw "The base-continuation additive increment did not begin after the projected anchor."
}

$defaults = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes/mir/settings/defaults.lua")
if ($defaults -notmatch 'linear_increment\s*=\s*0') { throw "Default linear increment must remain zero." }
$unknownFixture = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures/native-owner-unrecognized-formula/data-updates.lua")
if ($unknownFixture -notmatch 'L\^2') { throw "Unknown-formula fixture must remain outside the supported fixed/linear/exponential/hybrid family." }

Write-Host "[ok] unified ResearchCostModel identities, bounds, engine-normalized runtime preservation, and sixteen analytical transitions passed."
