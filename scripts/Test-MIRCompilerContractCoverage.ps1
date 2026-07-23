param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")))
$ErrorActionPreference = "Stop"
$manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\compiler-contract-coverage.yml") | ConvertFrom-Json
if ($manifest.schema -ne 1 -or -not $manifest.positive_negative_required) { throw "Compiler contract coverage manifest is invalid." }
$targetProfilePath = Join-Path $RepoRoot ([string]$manifest.technology_effect_target_profile)
$targetProfile = Get-Content -Raw -LiteralPath $targetProfilePath | ConvertFrom-Json
if ([int]$targetProfile.schema -ne 1 -or [string]$targetProfile.factorio_target -ne "2.1" -or
    [string]$targetProfile.factorio_api_version -ne "2.1.11") {
  throw "Technology-effect target profile is not bound to the governed Factorio 2.1.11 API."
}
$effectRuntime = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\integrity\effect_contracts.lua")
$effectContracts = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\domain\effects\generated_target_contracts.lua")
$technologyDesign = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\domain\technology\technology_design.lua")
& (Join-Path $RepoRoot "scripts\Update-MIRCompilerAuthorities.ps1") -RepoRoot $RepoRoot -Check
$hardGateProfile = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$manifest.technology_hard_gate_profile)) | ConvertFrom-Json
$hardGateRuntime = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\domain\technology\generated_hard_gate_authority.lua")
if ([int]$hardGateProfile.schema -ne 1 -or [string]::IsNullOrWhiteSpace([string]$hardGateProfile.authority)) {
  throw "Technology hard-gate authority is invalid."
}
foreach ($gate in @($hardGateProfile.gates)) {
  if (-not $hardGateRuntime.Contains('id = "' + [string]$gate.id + '"')) {
    throw "Generated hard-gate authority omits: $($gate.id)"
  }
}
$modifierTypes = @($targetProfile.target_bearing_modifiers | ForEach-Object { [string]$_.type })
if (@($modifierTypes | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
  throw "Technology-effect target profile contains duplicate modifier contracts."
}
foreach ($modifier in @($targetProfile.target_bearing_modifiers)) {
  $escapedType = [regex]::Escape([string]$modifier.type)
  $contractMatch = [regex]::Match($effectContracts, '(?s)\["' + $escapedType + '"\]\s*=\s*\{(?<body>.*?)(?=\n\s*\["|\n\})')
  if (-not $contractMatch.Success) {
    throw "MIR effect contracts omit target-bearing modifier: $($modifier.type)"
  }
  $contractBody = $contractMatch.Groups['body'].Value
  $targetFields = @($modifier.targets | ForEach-Object { [string]$_.field })
  if (@($targetFields | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
    throw "Technology-effect target profile duplicates a target field for $($modifier.type)."
  }
  foreach ($target in @($modifier.targets)) {
    $escapedField = [regex]::Escape([string]$target.field)
    $targetMatch = [regex]::Match($contractBody, '(?s)\{(?<body>[^{}]*field\s*=\s*"' + $escapedField + '"[^{}]*)\}')
    if (-not $targetMatch.Success) {
      throw "MIR effect contract omits $($modifier.type).$($target.field)."
    }
    $targetBody = $targetMatch.Groups['body'].Value
    foreach ($binding in @("resolver", "prototype_type")) {
      $expected = [string]$target.$binding
      if (-not [string]::IsNullOrWhiteSpace($expected) -and
          $targetBody -notmatch ([regex]::Escape($binding) + '\s*=\s*"' + [regex]::Escape($expected) + '"')) {
        throw "MIR effect contract has the wrong $binding for $($modifier.type).$($target.field)."
      }
    }
    $required = [bool]$target.required
    if ($targetBody -notmatch ('required\s*=\s*' + $(if ($required) { 'true' } else { 'false' }))) {
      throw "MIR effect contract has the wrong required policy for $($modifier.type).$($target.field)."
    }
    if ($null -ne $target.default -and
        $targetBody -notmatch ('default\s*=\s*"' + [regex]::Escape([string]$target.default) + '"')) {
      throw "MIR effect contract has the wrong default for $($modifier.type).$($target.field)."
    }
  }
}
if (-not $effectRuntime.Contains("function M.targets(effect)")) {
  throw "MIR effect contracts do not expose the shared target projection."
}
if (-not $technologyDesign.Contains("effect_contracts.targets(effect)")) {
  throw "TechnologyDesign does not consume the shared effect-target authority."
}
if ($technologyDesign.Contains('"turret_id", "fluid", "item"')) {
  throw "TechnologyDesign still carries a parallel effect-target field scanner."
}
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
foreach ($sentinel in @(
  "hard-safety sentinel",
  "duplicate materialized effect",
  "withhold and classify a missing-prerequisite operation",
  "withhold and classify the planned prerequisite SCC",
  "numeric effect value"
)) {
  if (-not $fixture.Contains($sentinel)) { throw "Compiler contract fixture is missing mutation sentinel: $sentinel" }
}
Write-Host "[ok] MIR compiler contract coverage, exhaustive target-bearing modifiers, and mutation sentinels are declared."
