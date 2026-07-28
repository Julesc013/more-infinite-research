param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context", "Executor")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}

$release = Get-MIRCPReleaseByVersion -Release "3.2.2" -RepoRoot $repo
$candidate = Join-Path $repo ([string]$release.package.archive)
if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
  & (Join-Path $repo "scripts/Build-MIRPackage.ps1") | Out-Host
}
$context = New-MIRCPVerificationContext -Mode calibrate-fresh -Target "2.1" -Release "3.2.2" -CandidatePath $candidate -OutputRoot "out/control-plane-v5-self-test/executor-contexts" -RepoRoot $repo
$evidenceRoot = "out/control-plane-v5-self-test/executor-evidence/$([guid]::NewGuid().ToString('N'))"
$contextResult = Write-MIRCPContextCompletionEvidence -ContextPath $context.path -TrustClass "self-test" -EvidenceRoot $evidenceRoot -RepoRoot $repo
$taskResult = Invoke-MIRCPTaskCommand -ContextPath $context.path -TaskId "harness.schemas" -TrustClass "self-test" -EvidenceRoot $evidenceRoot -RepoRoot $repo
if ([string]$contextResult.status -ne "passed" -or [string]$taskResult.status -ne "passed") { throw "Executor did not record exact passing task evidence." }
$index = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $evidenceRoot
$taskObjects = @($index.index.objects | Where-Object { $_.kind -eq "task-result" -and $_.status -eq "passed" })
if ($taskObjects.Count -ne 2) { throw "Executor evidence index does not contain exactly the context and test results." }
$aggregateFailedClosed = $false
try {
  [void](Complete-MIRCPAggregateGate -ContextPath $context.path -TrustClass "self-test" -EvidenceRoot $evidenceRoot -RepoRoot $repo)
} catch {
  if ($_.Exception.Message -match "lacks exact passing evidence") { $aggregateFailedClosed = $true } else { throw }
}
if (-not $aggregateFailedClosed) { throw "Aggregate gate accepted an incomplete evidence set." }
Write-Host "[ok] executor consumes one immutable context, writes exact task evidence, and aggregate evaluation fails closed on missing work."
