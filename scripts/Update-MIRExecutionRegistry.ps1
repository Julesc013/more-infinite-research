param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$Target = "2.1",
  [switch]$Check
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "scripts/MIRControlPlane/Core.ps1")
. (Join-Path $repo "scripts/MIRControlPlane/Scenario.ps1")
$registry = Update-MIRCPExecutionRegistry -Target $Target -RepoRoot $repo -Check:$Check
Write-Host "[ok] execution registry: $($registry.metrics.declarations) scenarios, $($registry.metrics.assertions) assertions, $($registry.metrics.batches) exact-environment batches, $($registry.metrics.projected_factorio_processes) projected Factorio processes."
