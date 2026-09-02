# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = "")
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $MirLegacyScriptRoot "..")).Path }

$manifestPath = Join-Path $RepoRoot ".mir\native-owner-cost-models.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ([int]$manifest.schema -ne 1) { throw "Unsupported native-owner cost-model schema." }
if ([string]$manifest.target -ne "2.1") { throw "Native-owner balance authority must target Factorio 2.1." }
if ([string]$manifest.source.factorio_version -ne "2.1.10") { throw "Native-owner source version drifted from the qualified Factorio binary." }
if ([string]$manifest.source.sha256 -notmatch '^[0-9A-F]{64}$') { throw "Native-owner source SHA-256 is malformed." }

$expected = [ordered]@{
  research_processing_unit = @{ owner = "processing-unit-productivity"; product = "processing-unit" }
  research_plastic = @{ owner = "plastic-bar-productivity"; product = "plastic-bar" }
  research_low_density_structure = @{ owner = "low-density-structure-productivity"; product = "low-density-structure" }
  research_rocket_fuel = @{ owner = "rocket-fuel-productivity"; product = "rocket-fuel" }
  research_steel = @{ owner = "steel-plate-productivity"; product = "steel-plate" }
}

$contracts = @($manifest.contracts)
if ($contracts.Count -ne $expected.Count) { throw "Expected exactly five native-owner balance contracts." }
$streamSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\streams\productivity.lua")
$settingsManifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\settings.yml")
$costModelSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\domain\native_owner\cost_model.lua")
$researchCostSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\domain\research_cost\model.lua")
$formulaSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\domain\research_cost\formula.lua")
$classificationSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\domain\research_cost\classification.lua")
$bindingSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\planner\native_owner_binding.lua")
$transitionSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\domain\research_cost\transition_descriptor.lua")
$emitterSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\emit\transactions\productivity_family_adoption.lua")
$runtimeSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\runtime\productivity_family_adoption.lua")
$progressFixtureSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\assert-native-owner-progress\control.lua")
$compilerContractFixtureSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\assert-compiler-contracts\data-final-fixes.lua")
$adoptionFixtureSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\assert-vanilla-family-adoption\data-final-fixes.lua")
$validationSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\Invoke-MIRValidation.ps1")

foreach ($contract in $contracts) {
  $stream = [string]$contract.stream
  if (-not $expected.Contains($stream)) { throw "Unexpected native-owner stream: $stream" }
  $row = $expected[$stream]
  if ([string]$contract.owner -ne $row.owner -or [string]$contract.product -ne $row.product) {
    throw "Native-owner mapping drifted for $stream."
  }
  if ([string]$contract.native.count_formula -ne "1.5^L*1000" -or [double]$contract.native.base -ne 1500 `
      -or [double]$contract.native.linear_increment -ne 0 `
      -or [double]$contract.native.growth -ne 1.5 -or [double]$contract.native.research_time -ne 60 `
      -or [string]$contract.native.max_level -ne "infinite" -or [double]$contract.native.effect_per_level -ne 0.1) {
    throw "Native Factorio 2.1 balance values drifted for $stream."
  }
  if ([double]$contract.mir_catalog_defaults.base -ne 8000 -or [double]$contract.mir_catalog_defaults.linear_increment -ne 0 `
      -or [double]$contract.mir_catalog_defaults.growth -ne 2 `
      -or [double]$contract.mir_catalog_defaults.research_time -ne 60 -or [double]$contract.mir_catalog_defaults.max_level -ne 0 `
      -or [double]$contract.mir_catalog_defaults.effect_percentage_points -ne 10) {
    throw "MIR catalog-default characterization drifted for $stream."
  }
  if ([string]$contract.default_policy -ne "preserve-final-owner-snapshot") {
    throw "Native-owner defaults must preserve the final owner snapshot for $stream."
  }
  $binding = 'native_owner_binding\("' + [regex]::Escape($row.owner) + '", \{"' + [regex]::Escape($row.product) + '"\}\)'
  if ($streamSource -notmatch $binding) { throw "Stream declaration is missing the governed native-owner binding for $stream." }
  if ($settingsManifest -notmatch "(?m)^  $([regex]::Escape($stream)):\r?\n    native_owner_binding: $([regex]::Escape($row.owner))\r?$") {
    throw "Settings manifest is missing the native-owner mapping for $stream."
  }
}

foreach ($prefix in @("ips-enable-%s", "ips-cost-base-%s", "ips-cost-linear-increment-%s", "ips-cost-growth-%s", "ips-max-level-%s", "ips-research-time-%s", "ips-effect-per-level-%s")) {
  if ($settingsManifest -notmatch [regex]::Escape($prefix)) { throw "Stable native-owner setting pattern missing: $prefix" }
}
foreach ($adapter in @('recognized-fixed-count', 'unrecognized-external-formula')) {
  if ($costModelSource -notmatch [regex]::Escape($adapter)) { throw "Native-owner formula adapter missing: $adapter" }
}
if ($classificationSource -notmatch '"recognized-"\s*\.\.') { throw "Research-cost classifier does not derive recognized styles from the canonical kind." }
foreach ($kind in @('fixed', 'linear', 'exponential', 'hybrid')) {
  if ($formulaSource -notmatch ('"' + [regex]::Escape($kind) + '"')) { throw "Research-cost formula kind missing: $kind" }
}
if ($researchCostSource -notmatch 'mir-research-cost-v1') { throw "ResearchCostModel formula ABI is missing." }
if ($compilerContractFixtureSource -notmatch 'native_model\.base\s*~=\s*1500' -or
    $compilerContractFixtureSource -notmatch 'configured_native\.count_formula\s*~=\s*"2000\*1\.25\^\(L-1\)"' -or
    $compilerContractFixtureSource -notmatch 'count_formula\s*=\s*"1000 \+ 100 \* L\^2"') {
  throw "Compiler-contract fixture must assert anchor-level native base cost and canonical configured formula output."
}
if ($adoptionFixtureSource -notmatch 'adoption_data\.version\s*==\s*4' -or
    $adoptionFixtureSource -notmatch 'schema=4\|stream=' -or
    $adoptionFixtureSource -notmatch '\|input-cost=' -or
    $adoptionFixtureSource -notmatch '\|output-cost=' -or
    $adoptionFixtureSource -notmatch '\|planned-max=') {
  throw "Vanilla-family adoption fixture must assert the schema-4 cost and maximum-level receipt ABI."
}
$costTrioIsAtomic = $bindingSource -match 'local cost_changed = base\.changed or linear_increment\.changed or growth\.changed' -and
  $bindingSource -match 'base = cost_changed and base\.value or nil' -and
  $bindingSource -match 'linear_increment = cost_changed and linear_increment\.value or nil' -and
  $bindingSource -match 'growth = cost_changed and growth\.value or nil'
if (-not $costTrioIsAtomic) {
  throw "Native-owner cost settings must activate the complete visible base/increment/growth trio."
}
if ($transitionSource -notmatch 'factorio-research-unit-count-floor-v1' -or
    $transitionSource -notmatch 'previous_cost' -or $transitionSource -notmatch 'current_cost') {
  throw "Native-owner transition descriptor does not bind realized old/new cost evidence."
}
if ($emitterSource -notmatch 'VERSION\s*=\s*4' -or
    $emitterSource -notmatch 'planned_max_level' -or
    $runtimeSource -match 'count_formula.*match') {
  throw "Native-owner runtime ABI is not descriptor-only schema 4 with maximum-level policy transport."
}
if ($progressFixtureSource -notmatch 'rows ~= 16' -or
    $progressFixtureSource -notmatch 'native-owner observed progress proof' -or
    $progressFixtureSource -notmatch 'current_research_unit_count' -or
    $progressFixtureSource -notmatch 'MIR changed Factorio-normalized completed research-unit work' -or
    $progressFixtureSource -notmatch 'over-budget evaluation did not fail closed' -or
    $validationSource -notmatch 'Assert-NativeOwnerResearchWorkPreserved' -or
    $validationSource -notmatch 'did not retain Factorio-normalized completed research-unit work') {
  throw "Native-owner lifecycle fixture does not prove the full transition matrix and safe refusal."
}

Write-Host "[ok] five Factorio 2.1 native-owner contracts and engine-normalized work preservation passed."
