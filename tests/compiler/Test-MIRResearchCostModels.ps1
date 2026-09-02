# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = "")
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
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
  CompatibilitySlice = "prototypes/mir/domain/research_cost/compatibility_slice.lua"
  CompatibilityAdapter = "prototypes/mir/emit/research_cost_compatibility_adapter.lua"
  ContractAuthority = ".mir/research-cost-contract-3.2.5.json"
  PublicArtifacts = "prototypes/mir/report/public_compiler_artifacts.lua"
  PublicArtifactBudget = "prototypes/mir/domain/compiler/public_artifact_budget.lua"
  ModData = "prototypes/mir/emit/mod_data.lua"
  Orchestrator = "prototypes/mir/pipeline/compiler_orchestrator.lua"
  AdoptionEmitter = "prototypes/mir/emit/transactions/productivity_family_adoption.lua"
  AdoptionRuntime = "prototypes/mir/runtime/productivity_family_adoption.lua"
  Streams = "prototypes/mir/planner/stream_compiler.lua"
  NativeCost = "prototypes/mir/domain/native_owner/cost_model.lua"
  Native = "prototypes/mir/planner/native_owner_binding.lua"
  Continuations = "prototypes/mir/planner/base_continuations.lua"
  MaximumLevel = "prototypes/mir/policy/max_level.lua"
  MaximumBinding = "prototypes/mir/domain/technology/maximum_level_binding.lua"
  RuntimeMaximum = "prototypes/mir/runtime/maximum_level_control.lua"
}
$source = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $path = Join-Path $RepoRoot $entry.Value
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing research-cost module: $($entry.Value)" }
  $source[$entry.Key] = Get-Content -Raw -LiteralPath $path
}

foreach ($required in @(
  "ips-cost-linear-increment-%s",
  "mir-cost-linear-increment-%s",
  "mir-research-cost-v1",
  "mir-research-cost-transition-v1",
  "mir-research-cost-qualification-v1",
  "mir-research-cost-algebraic-proof-v1",
  "mir-research-cost-compatibility-slice-v1",
  "mir-research-cost-neutral-default-parity-v1",
  "mir-research-cost-proof-assertion-v1",
  "mir-research-cost-support-public",
  "target-native-equivalent",
  "portable-with-adapter"
)) {
  if (($source.Values -join "`n") -notmatch [regex]::Escape($required)) { throw "Missing research-cost contract token: $required" }
}
foreach ($digest in @("semantic_digest", "authority_digest", "qualification_digest")) {
  if ($source.Model -notmatch $digest -or $source.Transition -notmatch $digest) {
    throw "Research-cost identity layer is missing: $digest"
  }
}
if ($source.AdoptionEmitter -notmatch 'VERSION\s*=\s*4' -or
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
foreach ($required in @(
  'compiler_input\.assert_trusted',
  'compiler_result\.assert_trusted',
  'result_phase\s*~=\s*"final"',
  'dimensions\.execution\s*~=\s*"APPLIED"',
  'semantic_set_fingerprint',
  'proof_assertion',
  'target_dispositions',
  'terminal\s*=\s*true',
  'neutral-default-semantic-parity-proven',
  'no-remediation-required',
  'validation-log'
)) {
  if ($source.CompatibilitySlice -notmatch $required) {
    throw "Research-cost compatibility slice is missing required fail-closed material: $required"
  }
}
if ($source.CompatibilitySlice -match 'data\.raw') {
  throw "Research-cost compatibility-slice domain authority must not inspect or mutate data.raw."
}
if ($source.CompatibilityAdapter -notmatch 'target_line\.mod_data_supported\(\)' -or
    $source.CompatibilityAdapter -notmatch 'emit_research_cost_compatibility' -or
    $source.CompatibilityAdapter -notmatch '\[MIR-RESEARCH-COST-SUPPORT\]') {
  throw "Research-cost compatibility support lacks its target-aware mod-data/validation-log adapter."
}
if ($source.ModData -notmatch 'more-infinite-research-research-cost-compatibility' -or
    $source.ModData -notmatch 'more-infinite-research\.research-cost-compatibility-public') {
  throw "Research-cost compatibility support is not emitted through the governed mod-data adapter."
}
if ($source.PublicArtifactBudget -notmatch '\["mir-research-cost-support-public"\]\s*=\s*16384' -or
    $source.PublicArtifacts -notmatch 'function M\.research_cost_compatibility') {
  throw "Research-cost compatibility support does not have a hard 16 KiB public projection budget."
}
$finalResultIndex = $source.Orchestrator.IndexOf('local final_result = context:state_view("final_compiler_result")')
$sliceIndex = $source.Orchestrator.IndexOf('research_cost_compatibility.build({')
if ($finalResultIndex -lt 0 -or $sliceIndex -le $finalResultIndex -or
    $source.Orchestrator -notmatch 'research_cost_compatibility_adapter"\)\.publish') {
  throw "Research-cost compatibility support must derive and publish only after final CompilerResult authority exists."
}
foreach ($budget in @(
  'formula_bytes\s*=\s*512',
  'tokens\s*=\s*128',
  'parse_depth\s*=\s*32',
  'ast_nodes\s*=\s*96',
  'absolute_numeric_literal\s*=\s*1e300',
  'absolute_exponent_constant\s*=\s*1000000',
  'evaluated_cost_out_of_bounds'
)) {
  if (($source.Values -join "`n") -notmatch $budget) { throw "Research-cost budget is missing: $budget" }
}
foreach ($proofMaterial in @(
  'function M\.algebraic_proof',
  'base_cost>=1',
  'linear_increment>=0',
  'growth_factor>=1',
  'maximum_exponent\s*=\s*100',
  'qualification_offset_out_of_bounds'
)) {
  if (($source.Values -join "`n") -notmatch $proofMaterial) {
    throw "Research-cost algebraic proof material is missing: $proofMaterial"
  }
}
if ($source.Transition -notmatch 'research_cost_model\.qualification_identity\(rebuilt\)') {
  throw "Transition descriptors must consume the canonical ResearchCostModel qualification identity."
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
foreach ($route in @("Streams", "Native", "Continuations", "MaximumLevel")) {
  if ($source[$route] -notmatch 'target_line\.feature_enabled\("scripted_techs"\)') {
    throw "$route may not make prototypes infinite without the governed scripted maximum-level controller."
  }
}
if ($source.ModData -notmatch 'target_line\.mod_data_supported\(\)' -or
    $source.RuntimeMaximum -notmatch 'if next\(managed\) == nil then' -or
    $source.RuntimeMaximum -notmatch 'add_runtime_settings_policy\(managed\)' -or
    $source.RuntimeMaximum -notmatch 'selected_maximum\(setting_name\)') {
  throw "Runtime maximum-level policy must use mod-data where supported and reconstruct the same binding from startup settings otherwise."
}
if ($source.MaximumBinding -match 'data\.raw|prototypes\.technology|target_line' -or
    $source.MaximumBinding -notmatch 'MIRMaximumLevelPolicyV3' -or
    $source.MaximumBinding -notmatch 'absolute-highest-technology-level' -or
    $source.MaximumBinding -notmatch 'exact-technology' -or
    $source.MaximumBinding -notmatch 'maximum_level_unknown_finalizer_adapter' -or
    $source.Orchestrator -notmatch 'maximum_level_binding\.from_plan' -or
    $source.ModData -notmatch 'maximum-level-policy-v3' -or
    $source.RuntimeMaximum -notmatch 'record_type == "MaximumLevelBinding"') {
  throw "Schema-3 MaximumLevelBinding must remain the pure normalized authority consumed by compiler transport and runtime."
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

$contract = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $paths.ContractAuthority) | ConvertFrom-Json
if ([int]$contract.schema -ne 1 -or [string]$contract.kind -ne "mir-research-cost-contract" -or
    [string]$contract.release -ne "3.2.5" -or [string]$contract.public_predecessor -ne "3.2.3" -or
    [string]$contract.authority_state -ne "product-complete-awaiting-source-freeze") {
  throw "The MIR 3.2.5 research-cost contract has invalid release authority."
}
if ([string]$contract.model.proof_abi -ne "mir-research-cost-algebraic-proof-v1" -or
    [int]$contract.model.bounds.qualification_offset -ne 100 -or
    [double]$contract.model.bounds.evaluated_cost.maximum -ne 1e300 -or
    [int]$contract.parser_bounds.formula_bytes -ne 512 -or
    [int]$contract.parser_bounds.tokens -ne 128 -or
    [int]$contract.parser_bounds.parse_depth -ne 32 -or
    [int]$contract.parser_bounds.ast_nodes -ne 96 -or
    [double]$contract.parser_bounds.absolute_numeric_literal -ne 1e300 -or
    [int]$contract.parser_bounds.absolute_exponent_constant -ne 1000000) {
  throw "The MIR 3.2.5 research-cost numeric/parser envelope is incomplete."
}
$kinds = @($contract.model.derived_kinds | ForEach-Object { [string]$_ })
if (($kinds -join ',') -ne 'fixed,linear,exponential,hybrid' -or
    [int]$contract.transition_matrix.rows -ne 16 -or
    -not [bool]$contract.transition_matrix.second_reload_required) {
  throw "The MIR 3.2.5 cost-kind or transition authority is incomplete."
}
$defaultVectors = @($contract.default_vectors | ForEach-Object { [string]$_.id })
foreach ($requiredVector in @('base-default','space-age-native-owner','automatic-family-creation','base-continuations','mod-set-configuration-change')) {
  if ($requiredVector -notin $defaultVectors) { throw "Missing exact 3.2.3 default vector: $requiredVector" }
}
$targetFeatures = @($contract.factorio_2_0_dispositions | ForEach-Object { [string]$_.feature })
foreach ($requiredFeature in @('cost-model','settings-and-profiles','progress-preservation','base-continuation','ownership-and-adoption','bounded-support-transport','migration-state','package-metadata','localization')) {
  if ($requiredFeature -notin $targetFeatures) { throw "Missing shipped-feature Factorio 2.0 disposition: $requiredFeature" }
}
if ([string]$contract.boundaries.factorio_2_0_release_authority -ne 'not-created' -or
    [string]$contract.boundaries.candidate_id -ne 'not-assigned') {
  throw "Research-cost product proof must not create candidate or Factorio 2.0 release authority."
}

Write-Host "[ok] unified ResearchCostModel identities, algebraic and parser bounds, exact defaults, target dispositions, and sixteen transitions passed."
