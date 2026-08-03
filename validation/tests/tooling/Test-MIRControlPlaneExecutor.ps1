param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context", "Executor")) {
  . (Join-Path $repo "tools/lib/control/$module.ps1")
}

$release = Get-MIRCPReleaseByVersion -Release "3.2.2" -RepoRoot $repo
$candidate = Join-Path $repo ([string]$release.package.archive)
if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
  & (Join-Path $repo "tools/commands/package/Build-MIRPackage.ps1") | Out-Host
}
$performanceSource = Join-Path $repo ".work/output/control-plane-v5-self-test/performance-sources/$([string]$release.package.source_commit)"
if (-not (Test-Path -LiteralPath $performanceSource -PathType Container)) {
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $performanceSource))
  & git -c "safe.directory=$repo" -c "safe.directory=$(Join-Path $repo '.git')" clone --local --no-hardlinks --no-checkout -- $repo $performanceSource 2>$null
  if ($LASTEXITCODE -ne 0) { throw "Could not clone exact performance source for executor self-test." }
  & git -C $performanceSource checkout --detach ([string]$release.package.source_commit) 2>$null
  if ($LASTEXITCODE -ne 0) { throw "Could not check out exact performance source for executor self-test." }
}
$historicalInputTask = [pscustomobject][ordered]@{
  id = "historical-input-self-test"
  effective_inputs = @("source:validation/tests/compiler/Test-MIRResearchCostModels.ps1")
}
$historicalInputArgs = @{
  Task = $historicalInputTask
  ReleaseRecord = $release
  Target = "2.1"
  SourceRepoRoot = $performanceSource
  RepoRoot = $repo
}
$historicalInputManifest = Get-MIRCPEffectiveInputManifest @historicalInputArgs
$historicalAbsence = @($historicalInputManifest.rows | Where-Object {
  [string]$_.input -eq "source:validation/tests/compiler/Test-MIRResearchCostModels.ps1" -and
  [string]$_.kind -eq "source-absent" -and
  [string]$_.source_commit -eq [string]$release.package.source_commit
})
if ($historicalAbsence.Count -ne 1) {
  throw "Historical exact-source absence is not explicit and commit-bound."
}
$currentAbsenceRejected = $false
try {
  $currentInputTask = [pscustomobject][ordered]@{
    id = "current-input-self-test"
    effective_inputs = @("source:does-not-exist/current-input.txt")
  }
  [void](Get-MIRCPEffectiveInputManifest -Task $currentInputTask -ReleaseRecord $release -Target "2.1" -RepoRoot $repo)
} catch {
  if ($_.Exception.Message -match "Exact-source TaskNode input is missing") {
    $currentAbsenceRejected = $true
  } else {
    throw
  }
}
if (-not $currentAbsenceRejected) {
  throw "Current-source exact input absence did not fail closed."
}
$context = New-MIRCPVerificationContext -Mode calibrate-fresh -Target "2.1" -Release "3.2.2" -CandidatePath $candidate `
  -SourceRepoRoot $performanceSource -OutputRoot ".work/output/control-plane-v5-self-test/executor-contexts" -RepoRoot $repo
$executionState = Get-MIRCPContextExecutionState -ContextPath $context.path -RepoRoot $repo
$canonicalCandidate = Get-MIRCPCanonicalCandidateArchive -State $executionState -RepoRoot $repo
$controlLock = Get-Content -Raw -LiteralPath (Join-Path $context.path "control-plane-lock.json") | ConvertFrom-Json
if ((Split-Path -Leaf $canonicalCandidate) -ne "more-infinite-research_3.2.2.zip" -or
    (Get-MIRCPSha256File -Path $canonicalCandidate) -ne [string]$release.package.archive_sha256 -or
    [int]$executionState.manifest.context_abi -ne 3 -or
    $null -eq $controlLock.PSObject.Properties["qualification_source_worktree_sha256"] -or
    @($controlLock.files | Where-Object path -eq "tools/lib/control/Executor.ps1").Count -ne 1 -or
    @($controlLock.files | Where-Object path -eq ".mir/control-plane/approved-delta-policies.json").Count -ne 1 -or
    @($controlLock.files | Where-Object path -eq ".mir/performance-campaign.json").Count -ne 1) {
  throw "Executor context lock or canonical immutable-candidate staging contract is incomplete."
}
$targetProfile = Get-Content -Raw -LiteralPath (Join-Path $context.path "target-profile.json") | ConvertFrom-Json
$candidateDescriptor = Get-Content -Raw -LiteralPath (Join-Path $context.path "candidate-descriptor.json") | ConvertFrom-Json
$performanceCampaignRelativePath = Get-MIRCPPerformanceCampaignRelativePath -Descriptor $candidateDescriptor -RepoRoot $repo
$performanceAuthority = Assert-MIRCPPerformanceCampaignAuthority -Path (Join-Path $repo $performanceCampaignRelativePath) `
  -Descriptor $candidateDescriptor -TargetProfile $targetProfile -RepoRoot $repo
if ([string]$performanceAuthority.campaign.candidate.candidate_id -ne "C24" -or
    [string]$performanceAuthority.campaign.candidate.archive_sha256 -ne [string]$release.package.archive_sha256 -or
    @($controlLock.files | Where-Object path -eq $performanceCampaignRelativePath).Count -ne 1) {
  throw "Controller performance authority is not bound to exact versioned C24 campaign."
}
$c30Release = Get-MIRCPReleaseByVersion -Release "3.2.3" -RepoRoot $repo
$c30Descriptor = [pscustomobject][ordered]@{
  release = [string]$c30Release.release
  candidate_id = [string]$c30Release.candidate_id
  target = [string]$c30Release.target
  source_commit = [string]$c30Release.package.source_commit
  source_sha256 = [string]$c30Release.package.source_sha256
  archive_sha256 = [string]$c30Release.package.archive_sha256
  content_sha256 = [string]$c30Release.package.content_sha256
}
$c30BaseProfile = Get-Content -Raw -LiteralPath (Join-Path $repo "validation/profiles/factorio-2.1.json") | ConvertFrom-Json
$c30Profile = Resolve-MIRCPTargetProfileForRelease -BaseProfile $c30BaseProfile -ReleaseRecord $c30Release -RepoRoot $repo
$c30CampaignRelativePath = Get-MIRCPPerformanceCampaignRelativePath -Descriptor $c30Descriptor -RepoRoot $repo
$c30Authority = Assert-MIRCPPerformanceCampaignAuthority -Path (Join-Path $repo $c30CampaignRelativePath) `
  -Descriptor $c30Descriptor -TargetProfile $c30Profile -RepoRoot $repo
if ([string]$c30Authority.campaign.baseline.version -ne "3.2.2" -or
    [string]$c30Authority.campaign.candidate.candidate_id -ne "C30") {
  throw "Controller performance authority is not bound to exact versioned C30 campaign."
}
$overlay = New-MIRCPPerformanceSourceOverlay -State $executionState `
  -Source ([pscustomobject][ordered]@{path=$performanceSource;commit=[string]$candidateDescriptor.source_commit}) `
  -Descriptor $candidateDescriptor -TargetProfile $targetProfile -RepoRoot $repo
$probePath = Join-Path $overlay.path ([string]$overlay.canonical_probe.path)
$probeBytes = [IO.File]::ReadAllBytes($probePath)
$sourceProbeText = [IO.File]::ReadAllText((Join-Path $performanceSource ([string]$overlay.canonical_probe.path))).Replace("`r`n", "`n").Replace("`r", "`n")
$overlayStatus = @(& git -C $overlay.path status --porcelain --untracked-files=all)
$compatAuditWrapperManifestRows = @($overlay.manifest.files | Where-Object { [string]$_.path -eq "scripts/Invoke-MIRCompatAudit.ps1" })
$controllerCompatAuditWrapperSha256 = Get-MIRCPSha256File -Path (Join-Path $repo "scripts/Invoke-MIRCompatAudit.ps1")
$compatAuditManifestRows = @($overlay.manifest.files | Where-Object { [string]$_.path -eq "tools/commands/compatibility/Invoke-MIRCompatAudit.ps1" })
$controllerCompatAuditSha256 = Get-MIRCPSha256File -Path (Join-Path $repo "tools/commands/compatibility/Invoke-MIRCompatAudit.ps1")
$performanceLibraryManifestRows = @($overlay.manifest.files | Where-Object { [string]$_.path -eq "tools/lib/validation/PerformanceCampaign.ps1" })
$controllerPerformanceLibrarySha256 = Get-MIRCPSha256File -Path (Join-Path $repo "tools/lib/validation/PerformanceCampaign.ps1")
$compatAuditText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools/commands/compatibility/Invoke-MIRCompatAudit.ps1")
$compatOutputResolveIndex = $compatAuditText.IndexOf('$resolvedOutputDir = [IO.Path]::GetFullPath($OutputDir)', [StringComparison]::Ordinal)
$compatOutputMaterializeIndex = $compatAuditText.IndexOf('$resolvedOutputDir = New-MIRDirectory -Path $resolvedOutputDir', [StringComparison]::Ordinal)
$compatLockIndex = $compatAuditText.IndexOf('$lockPath = Join-Path $resolvedOutputDir "compat-candidates.lock.json"', [StringComparison]::Ordinal)
if ([string]$overlay.package_source_sha256 -ne [string]$candidateDescriptor.source_sha256 -or
    [string]$overlay.canonical_probe.materialization -ne "utf8-no-bom-lf-v1" -or
    [string]$overlay.canonical_probe.sha256 -ne (Get-MIRCPSha256Text -Value $sourceProbeText) -or
    $probeBytes -contains [byte]13 -or
    [string]$overlay.manifest_sha256 -notmatch '^[0-9A-F]{64}$' -or
    [string]$overlay.harness_sha256 -notmatch '^[0-9A-F]{64}$' -or
    @($overlay.manifest.files).Count -ne 23 -or
    $compatAuditWrapperManifestRows.Count -ne 1 -or
    [string]$compatAuditWrapperManifestRows[0].sha256 -ne $controllerCompatAuditWrapperSha256 -or
    [string]$compatAuditWrapperManifestRows[0].materialization -ne "controller-exact-bytes-v1" -or
    $compatAuditManifestRows.Count -ne 1 -or
    [string]$compatAuditManifestRows[0].sha256 -ne $controllerCompatAuditSha256 -or
    [string]$compatAuditManifestRows[0].materialization -ne "controller-exact-bytes-v1" -or
    $performanceLibraryManifestRows.Count -ne 1 -or
    [string]$performanceLibraryManifestRows[0].sha256 -ne $controllerPerformanceLibrarySha256 -or
    [string]$performanceLibraryManifestRows[0].materialization -ne "controller-exact-bytes-v1" -or
    $compatOutputResolveIndex -lt 0 -or $compatOutputMaterializeIndex -le $compatOutputResolveIndex -or $compatLockIndex -le $compatOutputMaterializeIndex -or
    $overlayStatus.Count -ne 23 -or
    $overlayStatus -notcontains " M .mir/performance-campaign.json" -or
    $overlayStatus -notcontains " M fixtures/performance-regression-probe/data-final-fixes.lua" -or
    $overlayStatus -notcontains " M scripts/Invoke-MIRCompatAudit.ps1" -or
    $overlayStatus -notcontains "?? tools/commands/compatibility/Invoke-MIRCompatAudit.ps1" -or
    $overlayStatus -notcontains " M scripts/MIRCompatAudit/FactorioRunner.ps1" -or
    $overlayStatus -notcontains " M scripts/validation/PerformanceCampaign.ps1" -or
    $overlayStatus -notcontains "?? tools/lib/compatibility/FactorioRunner.ps1" -or
    $overlayStatus -notcontains "?? tools/lib/validation/PerformanceCampaign.ps1" -or
    $overlayStatus -notcontains "?? validation/scenarios/local-2.1.json") {
  throw "Performance source overlay is not exact, checkout-independent, and package-preserving."
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
}$c30Observation = Get-MIRCPZipPackageObservation -Path (Join-Path $repo "dist/more-infinite-research_3.2.3.zip")
$c30Paths = @{}
foreach ($file in @($c30Observation.files)) { $c30Paths[[string]$file.path] = [string]$file.sha256 }
$c30AddedPaths = @($c30Paths.Keys | Where-Object { -not $currentPaths.ContainsKey($_) } | Sort-Object)
$c30RemovedPaths = @($currentPaths.Keys | Where-Object { -not $c30Paths.ContainsKey($_) } | Sort-Object)
$c30ChangedPaths = @($c30Paths.Keys | Where-Object { $currentPaths.ContainsKey($_) -and $currentPaths[$_] -cne $c30Paths[$_] } | Sort-Object)
$c30DeltaPolicy = @($deltaAuthority.policies | Where-Object id -eq "c30-platform-logistics-hotfix-v1")
if ($c30DeltaPolicy.Count -ne 1 -or [string]$currentObservation.archive_sha256 -ne [string]$c30DeltaPolicy[0].baseline.archive_sha256 -or
    [string]$c30Observation.archive_sha256 -ne [string]$c30DeltaPolicy[0].candidate.archive_sha256 -or
    -not (Test-MIRCPExactPathSet -Expected @($c30DeltaPolicy[0].allowed_added_paths) -Actual $c30AddedPaths) -or
    -not (Test-MIRCPExactPathSet -Expected @($c30DeltaPolicy[0].allowed_removed_paths) -Actual $c30RemovedPaths) -or
    -not (Test-MIRCPExactPathSet -Expected @($c30DeltaPolicy[0].allowed_changed_paths) -Actual $c30ChangedPaths)) {
  throw "Native C30 approved-delta policy does not accept only the exact immutable 3.2.2-to-3.2.3 package delta."
}
$selectedC30Policies = @(Get-MIRCPNativePatchDeltaPolicy -Target "2.1" -FromVersion "3.2.2" -ToVersion "3.2.3" -CandidateId "C30" -RepoRoot $repo)
if ($selectedC30Policies.Count -ne 1 -or [string]$selectedC30Policies[0].id -ne "c30-platform-logistics-hotfix-v1") {
  throw "Public C30 approved-delta dispatch does not select the exact native C30 policy."
}
$evidenceRoot = ".work/output/control-plane-v5-self-test/executor-evidence/$([guid]::NewGuid().ToString('N'))"
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
  legacy_installation_sha256 = "E" * 64
  binary = [pscustomobject][ordered]@{bytes=10;sha256="A" * 64}
  official_data = [pscustomobject][ordered]@{file_count=2;sha256="B" * 64}
}
$syntheticLock = [pscustomobject][ordered]@{
  version = "self-test"
  installation_sha256 = "D" * 64
  binary = [pscustomobject][ordered]@{bytes=10;sha256="A" * 64}
  official_data = [pscustomobject][ordered]@{file_count=2;sha256="B" * 64}
}
$syntheticProfile = [pscustomobject]@{qualification_factorio_version="self-test"}
$materializedLock = New-MIRCPFactorioEnvironmentLock -Identity $syntheticIdentity -TargetProfile $syntheticProfile
$lockMatches = Test-MIRCPFactorioIdentityMatchesLock -Identity $syntheticIdentity -Lock $materializedLock
$legacyLock = [pscustomobject][ordered]@{
  version = "self-test"
  installation_sha256 = "E" * 64
  binary = [pscustomobject][ordered]@{bytes=10;sha256="A" * 64}
  official_data = [pscustomobject][ordered]@{file_count=2;sha256="B" * 64}
}
$legacyLockMatches = Test-MIRCPFactorioIdentityMatchesLock -Identity $syntheticIdentity -Lock $legacyLock
$wrongVersionRejected = $false
try {
  [void](New-MIRCPFactorioEnvironmentLock -Identity $syntheticIdentity -TargetProfile ([pscustomobject]@{qualification_factorio_version="other"}))
} catch {
  if ($_.Exception.Message -match "does not match target qualification version") { $wrongVersionRejected = $true } else { throw }
}
$syntheticLock.installation_sha256 = "C" * 64
$wrongInstallationRejected = -not (Test-MIRCPFactorioIdentityMatchesLock -Identity $syntheticIdentity -Lock $syntheticLock)
if (-not $lockMatches -or -not $legacyLockMatches -or -not $wrongVersionRejected -or -not $wrongInstallationRejected -or
    [string]$materializedLock.source -ne "context-materialization") {
  throw "Context and executor Factorio lock contracts are incomplete."
}
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
$scratchContextId = Get-MIRCPSha256Text -Value ("executor-path-budget/" + [guid]::NewGuid().ToString("N"))
$scratchState = [pscustomobject][ordered]@{context=[pscustomobject][ordered]@{context_id=$scratchContextId}}
$scratchCampaign = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/performance-campaign.json") | ConvertFrom-Json
$scratch = New-MIRCPCompactPerformanceArtifactRoot -State $scratchState -Campaign $scratchCampaign
$compatBudgetPath = Join-Path $scratch.path "medium-ecosystem.factorio-total\measured-25-candidate\compat\runs\u-0123456789ab\mods\mir-validation-settings-overrides\settings-updates.lua"
$scratchPayload = Join-Path $scratch.path "path-budget-self-test.txt"
"exact-context-bound-scratch" | Set-Content -LiteralPath $scratchPayload -Encoding UTF8
$scratchDestination = Join-Path $repo ".work/output/control-plane-v5-self-test/performance-artifact-relocation/$scratchContextId"
$scratchRelocation = Move-MIRCPPerformanceArtifacts -ExecutionRoot $scratch -Destination $scratchDestination
if ([string]$scratch.strategy -ne "compact-context-scratch-v1" -or
    [int]$scratch.maximum_factorio_path_length -gt [int]$scratch.conservative_path_budget -or
    [int]$scratch.maximum_factorio_path_length -lt $compatBudgetPath.Length -or
    [string]$scratchRelocation.context_id -ne $scratchContextId -or
    [int]$scratchRelocation.file_count -ne 2 -or
    (Test-Path -LiteralPath $scratch.path) -or
    -not (Test-Path -LiteralPath (Join-Path $scratchDestination "control-plane-execution-root.json") -PathType Leaf)) {
  throw "Compact performance staging or verified raw-artifact relocation is incomplete."
}
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
$repeatedStaticAggregate = Complete-MIRCPAggregateGate -ContextPath $context.path -AggregateTaskId "static.full" -TrustClass "self-test" -EvidenceRoot $evidenceRoot -RepoRoot $repo
$staticAggregateObjects = @((Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $evidenceRoot).index.objects | Where-Object {
  [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq "static.full" -and
  [string]$_.context_digest -eq [string]$executionState.context.context_id -and -not [bool]$_.revoked
})
if ([string]$staticAggregate.status -ne "passed" -or [string]$staticAggregate.aggregate_task -ne "static.full" -or
    [string]$repeatedStaticAggregate.status -ne "passed" -or $staticAggregateObjects.Count -ne 1) {
  throw "Static-only aggregate did not close independently and idempotently."
}
Write-Host "[ok] executor consumes one ABI-3 controller-locked immutable context with a target-version-bound Factorio installation seed, stages exact candidate bytes under Factorio's canonical archive name, constrains Factorio performance paths below the conservative Windows budget, relocates context-bound raw artifacts, natively evaluates the exact C24 four-path delta, scopes named aggregates idempotently, writes exact task evidence, rejects protected and hosted-runner spoofing, and fails closed on missing, ambiguous, or unknown work."
