param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")))
$ErrorActionPreference = "Stop"
$manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\compiler-contract-coverage.yml") | ConvertFrom-Json
if ($manifest.schema -ne 1 -or -not $manifest.positive_negative_required) { throw "Compiler contract coverage manifest is invalid." }
foreach ($field in @("generation_plan_gates", "actions", "family_strategies", "compatibility_pack_fields", "automatic_actions", "automatic_generation_controls", "automatic_creation_maturities", "automatic_policy_presets", "compiler_provider_fields", "diagnostic_code_namespaces", "legacy_automatic_modes", "mutation_sentinels")) {
  if (@($manifest.$field).Count -eq 0) { throw "Compiler contract coverage omits $field." }
}
$expectedActions = @("disabled", "preview", "apply")
if (@(Compare-Object $expectedActions @($manifest.automatic_actions)).Count -ne 0) { throw "Automatic action contract coverage is incomplete." }
if (($expectedActions -join "|") -ne (@($manifest.automatic_actions) -join "|")) { throw "Automatic actions must stay ordered from no changes to applied changes." }
$expectedMaturities = @("experimental", "reviewed")
if (($expectedMaturities -join "|") -ne (@($manifest.automatic_creation_maturities) -join "|")) { throw "Automatic creation maturities are incomplete or out of order." }
$contract = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\settings\automatic_compiler_contract.lua")
foreach ($snippet in @(
  'M.actions = {"disabled", "preview", "apply"}',
  'M.creation_maturities = {"experimental", "reviewed"}',
  'M.legacy_modes = {"off", "report", "safe-attach", "exact-pack", "safe-generate"}',
  'create_research = "mir-automatic-create-research"',
  'require_reviewed_data = "mir-automatic-require-reviewed-data"'
)) {
  if (-not $contract.Contains($snippet)) { throw "Automatic compiler contract is missing: $snippet" }
}
$expectedPresets = @("conservative", "safe", "expansive", "custom")
if (($expectedPresets -join "|") -ne (@($manifest.automatic_policy_presets) -join "|")) { throw "Automatic policy presets are incomplete or out of order." }
$providerContract = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\providers\contract.lua")
foreach ($field in @($manifest.compiler_provider_fields)) {
  if (-not $providerContract.Contains($field)) { throw "CompilerProvider contract is missing field: $field" }
}
$diagnostics = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\domain\diagnostics\codes.lua")
foreach ($namespace in @($manifest.diagnostic_code_namespaces)) {
  if (-not $diagnostics.Contains($namespace)) { throw "Compiler diagnostic registry is missing namespace: $namespace" }
}
$fixture = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $manifest.runtime_fixture)
foreach ($sentinel in @("hard-safety sentinel", "duplicate materialized effect", "missing prerequisite sentinel", "numeric effect value")) {
  if (-not $fixture.Contains($sentinel)) { throw "Compiler contract fixture is missing mutation sentinel: $sentinel" }
}
$effectProfilePath = Join-Path $RepoRoot ([string]$manifest.technology_effect_target_profile)
$effectProfile = Get-Content -Raw -LiteralPath $effectProfilePath | ConvertFrom-Json
if ([int]$effectProfile.schema -ne 1 -or [string]$effectProfile.factorio_target -ne "2.0.77") {
  throw "Technology-effect target profile must bind the qualified Factorio 2.0.77 target."
}
$effectContracts = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\integrity\effect_contracts.lua")
foreach ($modifier in @($effectProfile.target_bearing_modifiers)) {
  if (-not $effectContracts.Contains("[`"$([string]$modifier.type)`"]")) {
    throw "Technology-effect target contract is missing modifier: $($modifier.type)"
  }
  foreach ($target in @($modifier.targets)) {
    if (-not $effectContracts.Contains("field = `"$([string]$target)`"")) {
      throw "Technology-effect target contract is missing $($modifier.type).$target"
    }
  }
}
foreach ($required in @("unlock-quality", "turret-attack", "give-item")) {
  if (-not $fixture.Contains($required)) {
    throw "Compiler contract fixture is missing technology-effect coverage sentinel: $required"
  }
}
Write-Host "[ok] MIR compiler contracts, mutation sentinels, and Factorio 2.0 technology-effect targets are declared."
