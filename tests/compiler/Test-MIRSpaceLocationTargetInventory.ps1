# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'tools/lib/validation/CurrentTargetPackage.ps1')
$targetPackage = New-MIR4CurrentTargetPackageContext -RepoRoot $RepoRoot -Target 'f210'
$lookupPath = Resolve-MIR4CurrentTargetPackageOutputPath -Context $targetPackage -RelativePath 'prototypes/mir/platform/factorio/prototype_lookup.lua'
$inventoryPath = Resolve-MIR4CurrentTargetPackageOutputPath -Context $targetPackage -RelativePath 'prototypes/mir/platform/factorio/effect_target_inventory.lua'
$contractsPath = Resolve-MIR4CurrentTargetPackageOutputPath -Context $targetPackage -RelativePath 'prototypes/mir/domain/effects/generated_target_contracts.lua'

foreach ($path in @($lookupPath, $inventoryPath, $contractsPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Required space-location contract source is absent: $path"
  }
}

$lookup = Get-Content -Raw -LiteralPath $lookupPath
$inventory = Get-Content -Raw -LiteralPath $inventoryPath
$contracts = Get-Content -Raw -LiteralPath $contractsPath

if ($lookup -notmatch 'SPACE_LOCATION_TYPES\s*=\s*\{\s*"space-location"\s*,\s*"planet"\s*\}') {
  throw "SpaceLocationID lookup must include both space-location and planet prototype kinds."
}
if ($lookup -notmatch 'function\s+L\.space_location_types\s*\(') {
  throw "Prototype lookup does not expose the canonical space-location prototype-kind list."
}
if ($inventory -notmatch 'inventory\.resolvers\["space-location"\]\s*=\s*sorted_names\(lookup\.space_location_types\(\)\)') {
  throw "Effect target capture does not include concrete PlanetPrototype names."
}
if ($inventory -notmatch '\["space-location"\]\s*=\s*lookup\.space_location_types\(\)') {
  throw "Effect target postcondition does not compare both space-location prototype kinds."
}
if ($inventory -match 'sorted_names\(\{"space-location"\}\)') {
  throw "Legacy abstract-only space-location inventory is still present."
}
if ($contracts -notmatch '\["unlock-space-location"\]' -or
    $contracts -notmatch 'resolver\s*=\s*"space-location"') {
  throw "unlock-space-location is not bound to the canonical SpaceLocationID resolver."
}

Write-Host "[ok] unlock-space-location target inventory includes abstract space locations and concrete planets."
