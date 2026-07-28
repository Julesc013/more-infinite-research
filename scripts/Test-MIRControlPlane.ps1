param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [switch]$AllPackageLocks
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Evidence", "Views", "Shadow")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}

$records = Assert-MIRCPRecords -RepoRoot $repo
$freeze = Assert-MIRCPPackageFreeze -RepoRoot $repo -AllLocks:$AllPackageLocks

foreach ($schemaName in @("change-record.schema.json", "incident-record.schema.json", "release-record.schema.json")) {
  $schema = Read-MIRCPJson -Path "verification/schema/$schemaName" -RepoRoot $repo
  if ([string]$schema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or [string]$schema.type -ne "object" -or $schema.additionalProperties -ne $false) {
    throw "Control-plane schema is not strict JSON Schema 2020-12: $schemaName"
  }
}

$backport = Read-MIRCPJson -Path ".mir/backports/2.5.0.json" -RepoRoot $repo
if ([string]$backport.source.tag_state -ne "immutable" -or [string]$backport.source.tag_commit -ne "1138ed55ad7ad42e38cf9e821d1d4e7de5df6378") {
  throw "P9 backport authority is not bound to immutable tag 3.2.2."
}

$docManifest = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/docs.yml")
if ($docManifest -notmatch [regex]::Escape("docs/architecture/control-plane-v5.md")) {
  throw "Control Plane v5 architecture document is not registered."
}
$modules = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/modules.yml")
foreach ($token in @("control_plane_policy", "control_plane_entrypoint", "control_plane_gate")) {
  if ($modules -notmatch $token) { throw "Module manifest is missing $token." }
}

Write-Host "[ok] MIR Control Plane v5 records ($($records.changes) changes, $($records.incidents) incidents, $($records.releases) releases) and package freeze $($freeze.lock_id) are valid."
