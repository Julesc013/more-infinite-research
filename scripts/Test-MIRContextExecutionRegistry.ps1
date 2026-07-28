param(
  [Parameter(Mandatory)][string]$ContextPath,
  [Parameter(Mandatory)][string]$SourceRepoRoot,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$source = (Resolve-Path -LiteralPath $SourceRepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}
$context = Assert-MIRCPVerificationContext -Path $ContextPath
$manifest = Get-Content -Raw -LiteralPath (Join-Path $context.path "context-manifest.json") | ConvertFrom-Json
$descriptor = Get-Content -Raw -LiteralPath (Join-Path $context.path "candidate-descriptor.json") | ConvertFrom-Json
$sourceCommit = ([string](& git -C $source rev-parse HEAD)).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceCommit -ne [string]$descriptor.source_commit) {
  throw "Scenario registry source does not match the context package-source commit."
}
$registry = Get-Content -Raw -LiteralPath (Join-Path $context.path "expanded-scenarios.json") | ConvertFrom-Json
if ([string]$registry.target -ne [string]$manifest.target) { throw "Context registry target does not match its immutable manifest." }
$result = Assert-MIRCPExecutionRegistry -Registry $registry -RepoRoot $source
& (Join-Path $PSHOME "pwsh") -NoProfile -File (Join-Path $source "scripts/Test-MIRScenarioManifests.ps1") -RepoRoot $source
if ($LASTEXITCODE -ne 0) { throw "Exact-source scenario manifest validation failed with exit code $LASTEXITCODE." }
Write-Host "[ok] context registry binds source $sourceCommit and covers $($result.scenarios) scenarios, $($result.assertions) assertions, and $($result.batches) exact environments for target $($manifest.target)."
