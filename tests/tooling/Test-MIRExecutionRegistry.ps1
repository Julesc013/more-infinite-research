# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "tools/lib/control/Core.ps1")
. (Join-Path $repo "tools/lib/control/Scenario.ps1")

$registry = Update-MIRCPExecutionRegistry -Target "2.1" -RepoRoot $repo -Check
$result = Assert-MIRCPExecutionRegistry -Registry $registry -RepoRoot $repo
& (Join-Path $PSHOME "pwsh") -NoProfile -File (Join-Path $repo "tests/compatibility/Test-MIRScenarioManifests.ps1") -RepoRoot $repo
if ($LASTEXITCODE -ne 0) { throw "Legacy scenario manifest validation failed with exit code $LASTEXITCODE." }
Write-Host "[ok] execution registry covers $($result.scenarios) scenarios and $($result.assertions) assertions in $($result.batches) exact-environment batches; $($result.avoided_factorio_launches) Factorio launches are safely avoided and $($result.isolated_fallbacks) unresolved scenarios remain isolated."
