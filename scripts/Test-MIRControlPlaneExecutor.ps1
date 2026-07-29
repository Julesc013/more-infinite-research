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
$executionState = Get-MIRCPContextExecutionState -ContextPath $context.path -RepoRoot $repo
$canonicalCandidate = Get-MIRCPCanonicalCandidateArchive -State $executionState -RepoRoot $repo
$controlLock = Get-Content -Raw -LiteralPath (Join-Path $context.path "control-plane-lock.json") | ConvertFrom-Json
if ((Split-Path -Leaf $canonicalCandidate) -ne "more-infinite-research_3.2.2.zip" -or
    (Get-MIRCPSha256File -Path $canonicalCandidate) -ne [string]$release.package.archive_sha256 -or
    [int]$executionState.manifest.context_abi -ne 2 -or
    $null -eq $controlLock.PSObject.Properties["qualification_source_worktree_sha256"] -or
    @($controlLock.files | Where-Object path -eq "scripts/MIRControlPlane/Executor.ps1").Count -ne 1 -or
    @($controlLock.files | Where-Object path -eq ".mir/control-plane/approved-delta-policies.json").Count -ne 1) {
  throw "Executor context lock or canonical immutable-candidate staging contract is incomplete."
}
$baselineCandidate = Join-Path $repo "dist/more-infinite-research_3.2.1.zip"
$baselineObservation = Get-MIRCPZipPackageObservation -Path $baselineCandidate
$currentObservation = Get-MIRCPZipPackageObservation -Path $canonicalCandidate
$baselinePaths = @{}
foreach ($file in @($baselineObservation.files)) { $baselinePaths[[string]$file.path] = [string]$file.sha256 }
$currentPaths = @{}
foreach ($file in @($currentObservation.files)) { $currentPaths[[string]$file.path] = [string]$file.sha256 }
$addedPaths = @($currentPaths.Keys | Where-Object { -not $baselinePaths.ContainsKey($_) } | Sort-Object)
$removedPaths = @($baselinePaths.Keys | Where-Object { -not $currentPaths.ContainsKey($_) } | Sort-Object)
$changedPaths = @($currentPaths.Keys | Where-Object { $baselinePaths.ContainsKey($_) -and $baselinePaths[$_] -cne $currentPaths[$_] } | Sort-Object)
$deltaAuthority = Read-MIRCPJson -Path ".mir/control-plane/approved-delta-policies.json" -RepoRoot $repo
$deltaPolicy = @($deltaAuthority.policies | Where-Object id -eq "c24-four-path-hotfix-v1")
if ($deltaPolicy.Count -ne 1 -or [string]$baselineObservation.archive_sha256 -ne [string]$deltaPolicy[0].baseline.archive_sha256 -or
    [string]$currentObservation.archive_sha256 -ne [string]$deltaPolicy[0].candidate.archive_sha256 -or
    -not (Test-MIRCPExactPathSet -Expected @($deltaPolicy[0].allowed_added_paths) -Actual $addedPaths) -or
    -not (Test-MIRCPExactPathSet -Expected @($deltaPolicy[0].allowed_removed_paths) -Actual $removedPaths) -or
    -not (Test-MIRCPExactPathSet -Expected @($deltaPolicy[0].allowed_changed_paths) -Actual $changedPaths)) {
  throw "Native C24 approved-delta policy does not accept only the exact immutable four-path patch."
}
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
$syntheticIdentity = [pscustomobject][ordered]@{
  version = "self-test"
  installation_sha256 = "D" * 64
  binary = [pscustomobject][ordered]@{bytes=10;sha256="A" * 64}
  official_data = [pscustomobject][ordered]@{file_count=2;sha256="B" * 64}
}
$syntheticLock = [pscustomobject][ordered]@{
  version = "self-test"
  installation_sha256 = "D" * 64
  binary = [pscustomobject][ordered]@{bytes=10;sha256="A" * 64}
  official_data = [pscustomobject][ordered]@{file_count=2;sha256="B" * 64}
}
$lockMatches = Test-MIRCPFactorioIdentityMatchesLock -Identity $syntheticIdentity -Lock $syntheticLock
$syntheticLock.installation_sha256 = "C" * 64
$wrongInstallationRejected = -not (Test-MIRCPFactorioIdentityMatchesLock -Identity $syntheticIdentity -Lock $syntheticLock)
if (-not $lockMatches -or -not $wrongInstallationRejected) { throw "Executor Factorio lock comparison contract is incomplete." }
$protectedSpoofRejected = $false
try {
  [void](New-MIRCPExecutorProducer -TrustClass "protected-release" -RepoRoot $repo)
} catch {
  if ($_.Exception.Message -match "Protected-release producer") { $protectedSpoofRejected = $true } else { throw }
}
if (-not $protectedSpoofRejected) { throw "A local process could claim protected-release producer identity." }
$protectedFields = @(
  "GITHUB_REPOSITORY", "GITHUB_WORKFLOW", "GITHUB_EVENT_NAME", "GITHUB_REF", "MIR_PROTECTED_ENVIRONMENT",
  "MIR_TRUSTED_RUNNER", "RUNNER_ENVIRONMENT", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_JOB", "RUNNER_NAME"
)
$savedProtectedEnvironment = @{}
foreach ($field in $protectedFields) { $savedProtectedEnvironment[$field] = [Environment]::GetEnvironmentVariable($field, "Process") }
$hostedRunnerRejected = $false
try {
  $trustedLookingHostedRunner = @{
    GITHUB_REPOSITORY="Julesc013/more-infinite-research"; GITHUB_WORKFLOW="MIR Control Plane v5"; GITHUB_EVENT_NAME="workflow_dispatch";
    GITHUB_REF="refs/heads/toolchain/assurance-v5"; MIR_PROTECTED_ENVIRONMENT="release-candidate"; MIR_TRUSTED_RUNNER="self-hosted-windows";
    RUNNER_ENVIRONMENT="github-hosted"; GITHUB_RUN_ID="1"; GITHUB_RUN_ATTEMPT="1"; GITHUB_JOB="test"; RUNNER_NAME="hosted-test"
  }
  foreach ($entry in $trustedLookingHostedRunner.GetEnumerator()) { [Environment]::SetEnvironmentVariable([string]$entry.Key, [string]$entry.Value, "Process") }
  try { [void](New-MIRCPExecutorProducer -TrustClass "protected-release" -RepoRoot $repo) } catch {
    if ($_.Exception.Message -match "runner_environment") { $hostedRunnerRejected = $true } else { throw }
  }
} finally {
  foreach ($field in $protectedFields) { [Environment]::SetEnvironmentVariable($field, $savedProtectedEnvironment[$field], "Process") }
}
if (-not $hostedRunnerRejected) { throw "A hosted runner could claim the protected self-hosted identity." }
$unknownAggregateRejected = $false
try {
  [void](Complete-MIRCPAggregateGate -ContextPath $context.path -AggregateTaskId "not-an-aggregate" -TrustClass "self-test" -EvidenceRoot $evidenceRoot -RepoRoot $repo)
} catch {
  if ($_.Exception.Message -match "does not contain aggregate TaskNode") { $unknownAggregateRejected = $true } else { throw }
}
if (-not $unknownAggregateRejected) { throw "Aggregate subgraph selection accepted an unknown aggregate TaskNode." }
$selected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
[void]$selected.Add("static.full")
$changed = $true
while ($changed) {
  $changed = $false
  foreach ($row in @($executionState.plan.tasks | Where-Object { $selected.Contains([string]$_.id) })) {
    foreach ($dependency in @($row.depends_on)) { if ($selected.Add([string]$dependency)) { $changed = $true } }
  }
}
$existingIds = @((Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $evidenceRoot).index.objects | Where-Object kind -eq "task-result" | ForEach-Object { [string]$_.task_id })
foreach ($row in @($executionState.plan.tasks | Where-Object { $selected.Contains([string]$_.id) -and [string]$_.kind -ne "aggregate" -and $existingIds -notcontains [string]$_.id })) {
  [void](Write-MIRCPTaskResultEvidence -State $executionState -PlanRow $row -Status passed `
    -Payload ([pscustomobject][ordered]@{self_test=$true}) -TrustClass "self-test" -EvidenceRoot $evidenceRoot -RepoRoot $repo)
}
$staticAggregate = Complete-MIRCPAggregateGate -ContextPath $context.path -AggregateTaskId "static.full" -TrustClass "self-test" -EvidenceRoot $evidenceRoot -RepoRoot $repo
if ([string]$staticAggregate.status -ne "passed" -or [string]$staticAggregate.aggregate_task -ne "static.full") { throw "Static-only aggregate did not close independently." }
Write-Host "[ok] executor consumes one controller-locked immutable context, stages exact candidate bytes under Factorio's canonical archive name, natively evaluates the exact C24 four-path delta, scopes named aggregates, writes exact task evidence, rejects protected and hosted-runner spoofing, and fails closed on missing or unknown work."
