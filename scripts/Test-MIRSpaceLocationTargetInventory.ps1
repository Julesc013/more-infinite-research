param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$lookupPath = Join-Path $RepoRoot "prototypes\mir\platform\factorio\prototype_lookup.lua"
$inventoryPath = Join-Path $RepoRoot "prototypes\mir\platform\factorio\effect_target_inventory.lua"
$contractsPath = Join-Path $RepoRoot "prototypes\mir\domain\effects\generated_target_contracts.lua"

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
