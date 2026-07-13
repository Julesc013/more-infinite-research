param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }

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
}

$contracts = @($manifest.contracts)
if ($contracts.Count -ne $expected.Count) { throw "Expected exactly four native-owner balance contracts." }
$streamSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\streams\productivity.lua")
$settingsManifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\settings.yml")
$costModelSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\domain\native_owner\cost_model.lua")

foreach ($contract in $contracts) {
  $stream = [string]$contract.stream
  if (-not $expected.Contains($stream)) { throw "Unexpected native-owner stream: $stream" }
  $row = $expected[$stream]
  if ([string]$contract.owner -ne $row.owner -or [string]$contract.product -ne $row.product) {
    throw "Native-owner mapping drifted for $stream."
  }
  if ([string]$contract.native.count_formula -ne "1.5^L*1000" -or [double]$contract.native.base -ne 1000 `
      -or [double]$contract.native.growth -ne 1.5 -or [double]$contract.native.research_time -ne 60 `
      -or [string]$contract.native.max_level -ne "infinite" -or [double]$contract.native.effect_per_level -ne 0.1) {
    throw "Native Factorio 2.1 balance values drifted for $stream."
  }
  if ([double]$contract.mir_catalog_defaults.base -ne 8000 -or [double]$contract.mir_catalog_defaults.growth -ne 2 `
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

foreach ($prefix in @("ips-enable-%s", "ips-cost-base-%s", "ips-cost-growth-%s", "ips-max-level-%s", "ips-research-time-%s", "ips-effect-per-level-%s")) {
  if ($settingsManifest -notmatch [regex]::Escape($prefix)) { throw "Stable native-owner setting pattern missing: $prefix" }
}
foreach ($adapter in @('growth-to-level-times-base', 'base-times-growth-to-level-minus-one', 'recognized-fixed-count', 'unrecognized-external-formula')) {
  if ($costModelSource -notmatch [regex]::Escape($adapter)) { throw "Native-owner formula adapter missing: $adapter" }
}

Write-Host "[ok] four Factorio 2.1 native-owner balance contracts and safe formula adapters passed."
