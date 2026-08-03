param(
  [Parameter(Mandatory)][string]$ContextPath,
  [Parameter(Mandatory)][string]$SourceRepoRoot,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$source = (Resolve-Path -LiteralPath $SourceRepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}
$context = Assert-MIRCPVerificationContext -Path $ContextPath
$manifest = Get-Content -Raw -LiteralPath (Join-Path $context.path "context-manifest.json") | ConvertFrom-Json
$controlLock = Get-Content -Raw -LiteralPath (Join-Path $context.path "control-plane-lock.json") | ConvertFrom-Json
$sourceCommit = ([string](& git -C $source rev-parse HEAD)).Trim()
$sourceTree = ([string](& git -C $source rev-parse "HEAD^{tree}")).Trim()
$sourceWorktreeSha256 = Get-MIRCPTrackedWorktreeSha256 -SourceRepoRoot $source
if ($LASTEXITCODE -ne 0 -or $sourceCommit -ne [string]$controlLock.scenario_source_commit -or
    $sourceTree -ne [string]$controlLock.scenario_source_tree -or $sourceWorktreeSha256 -ne [string]$controlLock.scenario_source_worktree_sha256) {
  throw "Scenario registry source does not match the immutable context qualification-source lock."
}
$registry = Get-Content -Raw -LiteralPath (Join-Path $context.path "expanded-scenarios.json") | ConvertFrom-Json
if ([string]$registry.target -ne [string]$manifest.target) { throw "Context registry target does not match its immutable manifest." }
$result = Assert-MIRCPExecutionRegistry -Registry $registry -RepoRoot $source
& (Join-Path $PSHOME "pwsh") -NoProfile -File (Join-Path $source "validation/tests/compatibility/Test-MIRScenarioManifests.ps1") -RepoRoot $source
if ($LASTEXITCODE -ne 0) { throw "Exact-source scenario manifest validation failed with exit code $LASTEXITCODE." }
Write-Host "[ok] context registry binds source $sourceCommit and covers $($result.scenarios) scenarios, $($result.assertions) assertions, and $($result.batches) exact environments for target $($manifest.target)."
