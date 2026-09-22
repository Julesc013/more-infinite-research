# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/CurrentTargetPackage.ps1')

function Assert-MIR4NativeCoverage([bool]$Condition, [string]$Code) {
  if (-not $Condition) { throw "[mir4-native-effect-coverage-a20] $Code" }
}

function Read-MIR4NativeCoverageOutput($Context, [string]$Path) {
  return Get-MIR4CurrentTargetPackageOutputText -Context $Context -RelativePath $Path
}

function Assert-MIR4NativeCoverageBound($Context, [string]$Path) {
  $entry = $null
  Assert-MIR4NativeCoverage $Context.outputs.TryGetValue($Path, [ref]$entry) "undeclared-output:$($Context.target):$Path"
  $actual = (Get-FileHash -LiteralPath ([string]$entry.source_file) -Algorithm SHA256).Hash
  Assert-MIR4NativeCoverage ($actual -ceq [string]$entry.source_sha256) "source-bytes:$($Context.target):$Path"
  Assert-MIR4NativeCoverage ([string]$entry.source_sha256 -ceq [string]$entry.output_sha256) "package-bytes:$($Context.target):$Path"
}

$f210 = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target 'f210'
$f200 = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target 'f200'
$f110 = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target 'f110'
$f100 = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target 'f100'
$allTargets = @($f210, $f200, $f110, $f100)

$commonPaths = @(
  'prototypes/streams/direct-effects.lua',
  'prototypes/mir/policy/native_effect_coverage.lua',
  'prototypes/mir/policy/weapon_speed.lua',
  'prototypes/mir/planner/compilation_plan/build.lua',
  'prototypes/mir/capabilities/registry.lua',
  'prototypes/mir/index/registry_builder.lua'
)
foreach ($context in $allTargets) {
  foreach ($path in $commonPaths) { Assert-MIR4NativeCoverageBound $context $path }
}
Assert-MIR4NativeCoverageBound $f210 'prototypes/mir/planner/stream_compiler/qualify.lua'
Assert-MIR4NativeCoverageBound $f200 'prototypes/mir/planner/stream_compiler/qualify.lua'

$direct = Read-MIR4NativeCoverageOutput $f210 'prototypes/streams/direct-effects.lua'
$expectedStreams = [ordered]@{
  research_rocket_shooting_speed = @('rocket')
  research_cannon_shooting_speed = @('cannon-shell')
  research_flamethrower_shooting_speed = @('flamethrower')
  research_electric_shooting_speed = @('tesla', 'electric')
}
foreach ($stream in $expectedStreams.GetEnumerator()) {
  $match = [regex]::Match($direct, '(?ms)^  ' + [regex]::Escape($stream.Key) + '\s*=\s*\{(?<body>.*?)^  \},$')
  Assert-MIR4NativeCoverage $match.Success "direct-stream-missing:$($stream.Key)"
  $body = $match.Groups['body'].Value
  Assert-MIR4NativeCoverage ($body -match 'adopt_exact_native_effect_owner\s*=\s*true') "direct-owner-policy:$($stream.Key)"
  foreach ($category in @($stream.Value)) {
    Assert-MIR4NativeCoverage ($body -match ('type\s*=\s*"gun-speed"[\s\S]*?ammo_category\s*=\s*"' + [regex]::Escape($category) + '"')) "direct-category:$($stream.Key):$category"
  }
}

$coverage = Read-MIR4NativeCoverageOutput $f210 'prototypes/mir/policy/native_effect_coverage.lua'
foreach ($snippet in @(
  'function M.identity_owner_names',
  'positive_numeric_value = true',
  'function M.resolve_direct_effect_ownership',
  'function M.direct_effect_diagnostics',
  'function M.is_mir_generated_stream',
  'function M.is_mir_weapon_speed_base_extension_owner',
  'entry.kind == "base_extension"',
  'function M.technology_effect_identity_qualification_reason',
  'technology_not_infinite',
  'technology_science_unreachable',
  'effect_identity_nonpositive_or_non_numeric',
  'local is_gun_speed = effect and effect.type == "gun-speed"',
  'positive-effect-and-single-owner-required',
  'not-proven-by-static-analysis'
)) {
  Assert-MIR4NativeCoverage $coverage.Contains($snippet) "coverage-contract:$snippet"
}
Assert-MIR4NativeCoverage (-not $coverage.Contains('function M.is_weapon_speed_continuation_owner')) 'coverage-reject-numbered-name-only'

foreach ($context in @($f210, $f200)) {
  $qualifier = Read-MIR4NativeCoverageOutput $context 'prototypes/mir/planner/stream_compiler/qualify.lua'
  foreach ($snippet in @(
    'native_effect_coverage.resolve_direct_effect_ownership(direct_effects)',
    'covered_by_existing_infinite_native_modifier',
    'no_useful_native_effect_increment',
    'native_effect_paid_noop_guard'
  )) {
    Assert-MIR4NativeCoverage $qualifier.Contains($snippet) "qualifier-contract:$($context.target):$snippet"
  }
}

$basePlan = Read-MIR4NativeCoverageOutput $f210 'prototypes/mir/planner/compilation_plan/build.lua'
foreach ($snippet in @(
  'local function gun_speed_category',
  'local function owner_list_contains_non_continuation',
  'is_mir_weapon_speed_base_extension_owner(owner)',
  'weapon-speed-overlap-resolved',
  'weapon-speed-native-owner-preserved',
  'diagnostics.native_effect_covered_categories',
  'external owner of Tesla',
  'without such an owner'
)) {
  Assert-MIR4NativeCoverage $basePlan.Contains($snippet) "base-plan-contract:$snippet"
}
Assert-MIR4NativeCoverage (-not $basePlan.Contains('ammo_category == "rocket"')) 'base-plan-rocket-hardcode'
Assert-MIR4NativeCoverage (-not $basePlan.Contains('ammo_category == "cannon-shell"')) 'base-plan-cannon-hardcode'
Assert-MIR4NativeCoverage (-not $basePlan.Contains('planned_overlap_identities = {')) 'base-plan-retained-overlap'

$weaponPolicy = Read-MIR4NativeCoverageOutput $f210 'prototypes/mir/policy/weapon_speed.lua'
foreach ($snippet in @(
  'require("prototypes.mir.platform.factorio.data_raw")',
  'require("prototypes.streams.direct-effects")',
  'local function has_non_continuation_owner',
  'is_mir_weapon_speed_base_extension_owner(owner)',
  'identity_owner_names(effect',
  'A category can leave the general continuation only when the exact positive',
  'mode == "off" then return {}'
)) {
  Assert-MIR4NativeCoverage $weaponPolicy.Contains($snippet) "weapon-policy-contract:$snippet"
}
Assert-MIR4NativeCoverage (-not $weaponPolicy.Contains('local replacements = {')) 'weapon-policy-hardcoded-replacements'
Assert-MIR4NativeCoverage (-not $weaponPolicy.Contains('rocket = true')) 'weapon-policy-unconditional-rocket'

$capabilities = Read-MIR4NativeCoverageOutput $f210 'prototypes/mir/capabilities/registry.lua'
foreach ($snippet in @(
  'request_id = "NATIVE-01"',
  'request_id = "STACK-02"',
  'semantic_scope = "ammo-category-firing-rate"',
  'semantic_scope = "belt-lane-item-stack-size"',
  'semantic_scope = "inserter-held-item-stack-size"',
  'semantic_scope = "stack-inserter-held-item-capacity"',
  'semantic_scope = "bulk-inserter-held-item-capacity"',
  'no-mir-emission-without-cap-and-conservation-proof',
  'current_mir_base_continuation = "unqualified-pending-exact-cap-and-conservation-proof"',
  'existing_mir_base_continuation_pending_exact_cap_and_conservation_proof',
  'report_existing_mir_base_continuation_pending_exact_proof',
  'qualified_external_owners',
  'unqualified_sightings',
  'technology_effect_identity_qualification_reason',
  'withhold_until_exact_observation',
  'current_emission_status'
)) {
  Assert-MIR4NativeCoverage $capabilities.Contains($snippet) "capability-diagnostic:$snippet"
}
foreach ($effectType in @('belt-stack-size-bonus', 'inserter-stack-size-bonus', 'stack-inserter-capacity-bonus', 'bulk-inserter-capacity-bonus')) {
  Assert-MIR4NativeCoverage $capabilities.Contains('"' + $effectType + '"') "stack-type:$effectType"
}

$registryBuilder = Read-MIR4NativeCoverageOutput $f210 'prototypes/mir/index/registry_builder.lua'
Assert-MIR4NativeCoverage $registryBuilder.Contains('generated_registry.get(tech_name).kind == "stream"') 'registry-mir-stream-owner'
Assert-MIR4NativeCoverage $registryBuilder.Contains('native_continuation_owner') 'registry-native-continuation-owner'
Assert-MIR4NativeCoverage $registryBuilder.Contains('effect = deepcopy(effect)') 'registry-owner-exact-effect-evidence'

$fixtureSource = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/weapon-speed-external-owner/data.lua')
Assert-MIR4NativeCoverage $fixtureSource.Contains('name = "weapon-shooting-speed-99"') 'precompilation-external-numbered-continuation'
Assert-MIR4NativeCoverage $fixtureSource.Contains('Pre-compilation external numbered continuation') 'precompilation-external-numbered-purpose'
$fixture = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/assert-weapon-speed-safety/data-final-fixes.lua')
Assert-MIR4NativeCoverage $fixture.Contains('mode ~= "off" and replacement_coverage(category)') 'engine-fixture-owner-gate'
Assert-MIR4NativeCoverage (-not $fixture.Contains('mode == "always"')) 'engine-fixture-no-unowned-always-strip'
Assert-MIR4NativeCoverage $fixture.Contains('pre-compilation external numbered continuation was not present') 'engine-fixture-precompilation-counterexample'
Assert-MIR4NativeCoverage $fixture.Contains('external weapon shooting speed continuation was mutated') 'engine-fixture-numbered-owner-preserved'
foreach ($reason in @(
  'technology_not_infinite',
  'technology_disabled',
  'effect_identity_nonpositive_or_non_numeric',
  'technology_science_unreachable'
)) {
  Assert-MIR4NativeCoverage $fixture.Contains($reason) "engine-fixture-unqualified-native-owner:$reason"
}

# The F100/F110 package mappings must carry the same exact-owner semantics as
# F200/F210. This is a package-bound semantic assertion: it verifies the
# materialized bytes for direct coverage, owner qualification, mixed Tesla /
# electric category handling, and existing STACK-02 continuation reporting.
foreach ($context in $allTargets) {
  $targetCoverage = Read-MIR4NativeCoverageOutput $context 'prototypes/mir/policy/native_effect_coverage.lua'
  $targetPlan = Read-MIR4NativeCoverageOutput $context 'prototypes/mir/planner/compilation_plan/build.lua'
  $targetCapabilities = Read-MIR4NativeCoverageOutput $context 'prototypes/mir/capabilities/registry.lua'
  Assert-MIR4NativeCoverage $targetCoverage.Contains('entry.kind == "base_extension"') "target-numbered-owner-registry:$($context.target)"
  Assert-MIR4NativeCoverage $targetCoverage.Contains('covered_categories') "target-mixed-category-coverage:$($context.target)"
  Assert-MIR4NativeCoverage $targetPlan.Contains('external owner of Tesla') "target-mixed-tesla-electric-owner:$($context.target)"
  Assert-MIR4NativeCoverage $targetCapabilities.Contains('existing_mir_base_continuation_pending_exact_cap_and_conservation_proof') "target-stack-existing-emission:$($context.target)"
}

[pscustomobject][ordered]@{
  status = 'passed'
  test_id = 'static.mir4-native-effect-coverage-a20'
  targets = @('f210', 'f200', 'f110', 'f100')
  native_request = 'NATIVE-01'
  stack_request = 'STACK-02'
  direct_categories = @('rocket', 'cannon-shell', 'flamethrower', 'tesla', 'electric')
  engine_execution = 'not-run'
  public_qualification_claim = 'not-made'
} | ConvertTo-Json -Depth 8
