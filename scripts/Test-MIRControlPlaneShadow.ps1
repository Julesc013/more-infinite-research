param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Evidence", "Views", "Shadow")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}

$shadow = Assert-MIRCPShadowContract -RepoRoot $repo
Write-Host "[ok] v4/v5 shadow contract covers $($shadow.dimensions) dimensions and $($shadow.candidates) calibration candidates; acceptance remains $($shadow.state)."
