function Invoke-MIRCPPerformanceMeasurement {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$PriorRelease,
    [string]$LocalModZipDir = "",
    [string]$TrustClass = "protected-release",
    [string]$EvidenceRoot = "",
    [string]$SourceRepoRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $repo
  $source = Assert-MIRCPExecutionSource -State $state -SourceRepoRoot $SourceRepoRoot
  $candidate = Get-MIRCPCanonicalCandidateArchive -State $state -RepoRoot $repo
  $factorio = Assert-MIRCPFactorioContextLock -State $state -FactorioBin $FactorioBin
  $row = @($state.plan.tasks | Where-Object id -eq "performance.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain performance.measurement exactly once." }
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $profile = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "target-profile.json") | ConvertFrom-Json
  $overlay = New-MIRCPPerformanceSourceOverlay -State $state -Source $source -Descriptor $descriptor -TargetProfile $profile -RepoRoot $repo
  $outputRoot = Join-Path $repo "build/results/control-plane-v5/performance/$([string]$state.context.context_id)"
  $outputPath = Join-Path $outputRoot "evidence.json"
  $executionRoot = New-MIRCPCompactPerformanceArtifactRoot -State $state -Campaign $overlay.authority.campaign
  $artifactDestination = Join-Path $outputRoot "artifacts"
  $arguments = @{
    RepoRoot = $overlay.path
    Candidate = $candidate
    PriorRelease = $PriorRelease
    FactorioBin = $factorio.path
    ExpectedSourceCommit = [string]$source.commit
    ExpectedBaselineVersion = [string]$profile.upgrade.from_version
    ExpectedFactorioVersion = [string]$profile.qualification_factorio_version
    OutputPath = $outputPath
    ArtifactRoot = [string]$executionRoot.path
  }
  if (-not [string]::IsNullOrWhiteSpace($LocalModZipDir)) { $arguments.LocalModZipDir = $LocalModZipDir }
  $measurementError = $null
  $relocationError = $null
  $relocation = $null
  $exitCode = 1
  try {
    & (Join-Path $overlay.path "scripts/Invoke-MIRPerformanceQualification.ps1") @arguments
    $exitCode = $LASTEXITCODE
  } catch {
    $measurementError = $_
  } finally {
    try {
      $relocation = Move-MIRCPPerformanceArtifacts -ExecutionRoot $executionRoot -Destination $artifactDestination
    } catch {
      $relocationError = $_
    }
  }
  if ($null -ne $relocationError) {
    if ($null -ne $measurementError) {
      throw "Performance measurement failed ('$($measurementError.Exception.Message)') and raw-artifact relocation also failed ('$($relocationError.Exception.Message)')."
    }
    throw $relocationError
  }
  if ($null -ne $measurementError) { throw $measurementError }
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw "Performance measurement produced no compact evidence." }
  $evidence = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json
  $failedLanes = @($evidence.lanes | Where-Object { [string]$_.status -ne "passed" })
  $expectedLaneIds = @(@($overlay.authority.campaign.lanes | ForEach-Object { [string]$_.id }) + @($overlay.authority.campaign.phase_lanes | ForEach-Object { [string]$_.id }))
  $actualLaneIds = @($evidence.lanes | ForEach-Object { [string]$_.id })
  $laneSetExact = $actualLaneIds.Count -eq $expectedLaneIds.Count -and
    @($actualLaneIds | Sort-Object -Unique).Count -eq $actualLaneIds.Count -and
    (Test-MIRCPExactPathSet -Expected $expectedLaneIds -Actual $actualLaneIds)
  $priorSha256 = Get-MIRCPSha256File -Path (Resolve-Path -LiteralPath $PriorRelease).Path
  $baseline = Get-MIRCPReleaseByVersion -Release ([string]$profile.upgrade.from_version) -RepoRoot $repo
  $status = if ($exitCode -eq 0 -and [int]$evidence.schema -eq 3 -and [string]$evidence.kind -eq "mir-runtime-performance-regression" -and
    [string]$evidence.status -eq "passed" -and $failedLanes.Count -eq 0 -and $laneSetExact -and
    [string]$evidence.candidate.version -eq [string]$descriptor.release -and
    [string]$evidence.candidate.archive_sha256 -eq [string]$descriptor.archive_sha256 -and
    [string]$evidence.candidate.package_content_sha256 -eq [string]$descriptor.content_sha256 -and
    [string]$evidence.candidate.source_commit -eq [string]$source.commit -and
    [string]$evidence.baseline.version -eq [string]$baseline.release -and
    [string]$evidence.baseline.archive_sha256 -eq $priorSha256 -and
    [string]$evidence.baseline.package_content_sha256 -eq [string]$baseline.package.content_sha256 -and
    [string]$evidence.factorio.version -eq [string]$profile.qualification_factorio_version -and
    [string]$evidence.factorio.binary_sha256 -eq [string]$factorio.binary.sha256 -and
    [string]$evidence.comparability.scenarios_sha256 -eq [string]$overlay.authority_sha256 -and
    [string]$evidence.comparability.harness_sha256 -eq [string]$overlay.harness_sha256 -and
    [int]$evidence.run_policy.warmup_runs -eq [int]$overlay.authority.campaign.run_policy.warmup_runs -and
    [int]$evidence.run_policy.minimum_measured_runs_per_package -eq [int]$overlay.authority.campaign.run_policy.minimum_measured_runs_per_package -and
    [string]$evidence.run_policy.order -eq [string]$overlay.authority.campaign.run_policy.order) { "passed" } else { "failed" }
  $facts = [pscustomobject][ordered]@{
    status = $status
    measurement_mode = "paired-balanced-native-v3"
    execution_root_strategy = [string]$relocation.strategy
    conservative_path_budget = [int]$relocation.conservative_path_budget
    maximum_factorio_path_length = [int]$relocation.maximum_factorio_path_length
    raw_artifact_file_count = [int]$relocation.file_count
    raw_artifact_bytes = [int64]$relocation.bytes
    raw_artifact_tree_sha256 = [string]$relocation.artifact_tree_sha256
    campaign_authority_sha256 = [string]$overlay.authority_sha256
    overlay_manifest_sha256 = [string]$overlay.manifest_sha256
    canonical_probe_sha256 = [string]$overlay.canonical_probe.sha256
    harness_sha256 = [string]$overlay.harness_sha256
    package_source_sha256 = [string]$overlay.package_source_sha256
    factorio_installation_sha256 = [string]$factorio.installation_sha256
    factorio_binary_sha256 = [string]$factorio.binary.sha256
    prior_archive_sha256 = $priorSha256
    lane_count = @($evidence.lanes).Count
    expected_lane_count = $expectedLaneIds.Count
    lane_set_exact = $laneSetExact
    failed_lane_count = $failedLanes.Count
    third_party_closure_sha256 = [string]$evidence.comparability.third_party_closure_sha256
    artifact_status = [string]$evidence.status
  }
  return Write-MIRCPSpecializedTaskEvidence -State $state -PlanRow $row[0] -ObservationKind engine-realization -Status $status `
    -EnvironmentMaterial ([pscustomobject][ordered]@{task=[string]$row[0].effective_input_sha256;factorio=$factorio;prior_archive_sha256=$priorSha256;source_commit=[string]$source.commit;campaign_authority_sha256=[string]$overlay.authority_sha256;overlay_manifest_sha256=[string]$overlay.manifest_sha256;harness_sha256=[string]$overlay.harness_sha256;execution_root_strategy=[string]$facts.execution_root_strategy;conservative_path_budget=[int]$facts.conservative_path_budget;maximum_factorio_path_length=[int]$facts.maximum_factorio_path_length;raw_artifact_tree_sha256=[string]$facts.raw_artifact_tree_sha256;third_party_closure_sha256=[string]$facts.third_party_closure_sha256}) `
    -Facts $facts -ArtifactPath $outputPath -ArtifactKind "runtime-performance-evidence" -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
}

function Invoke-MIRCPUpgradeMeasurement {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$PriorRelease,
    [Parameter(Mandatory)][string]$SourceRepoRoot,
    [string]$TrustClass = "protected-release",
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $repo
  $source = Assert-MIRCPExecutionSource -State $state -SourceRepoRoot $SourceRepoRoot
  $candidate = Get-MIRCPCanonicalCandidateArchive -State $state -RepoRoot $repo
  $row = @($state.plan.tasks | Where-Object id -eq "upgrade.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain upgrade.measurement exactly once." }
  $profile = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "target-profile.json") | ConvertFrom-Json
  $factorio = Assert-MIRCPFactorioContextLock -State $state -FactorioBin $FactorioBin
  $prior = (Resolve-Path -LiteralPath $PriorRelease).Path
  $outputPath = Join-Path $repo "build/results/control-plane-v5/upgrade-evidence.json"
  & (Join-Path $source.path "tests/runtime/Test-MIRUpgradeMatrix.ps1") -RepoRoot $source.path `
    -FactorioBin $factorio.path -FromZip $prior -ToZip $candidate `
    -FromVersion ([string]$profile.upgrade.from_version) -ToVersion ([string]$profile.upgrade.to_version) `
    -FixtureName ([string]$profile.upgrade.fixture) -OutputPath $outputPath
  $exitCode = $LASTEXITCODE
  $evidence = if (Test-Path -LiteralPath $outputPath -PathType Leaf) { Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json } else { $null }
  $status = if ($exitCode -eq 0 -and $null -ne $evidence -and [string]$evidence.status -eq "passed") { "passed" } else { "failed" }
  $facts = [pscustomobject][ordered]@{
    status = $status
    from_version = [string]$profile.upgrade.from_version
    to_version = [string]$profile.upgrade.to_version
    fixture = [string]$profile.upgrade.fixture
    prior_archive_sha256 = Get-MIRCPSha256File -Path $prior
    factorio_installation_sha256 = [string]$factorio.installation_sha256
    factorio_binary_sha256 = [string]$factorio.binary.sha256
    evidence_status = if ($null -eq $evidence) { "missing" } else { [string]$evidence.status }
  }
  return Write-MIRCPSpecializedTaskEvidence -State $state -PlanRow $row[0] -ObservationKind engine-realization -Status $status `
    -EnvironmentMaterial ([pscustomobject][ordered]@{task=[string]$row[0].effective_input_sha256;factorio=$factorio;prior_archive_sha256=$facts.prior_archive_sha256;source_commit=[string]$source.commit}) `
    -Facts $facts -ArtifactPath $outputPath -ArtifactKind "upgrade-evidence" -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
}

function Invoke-MIRCPEcosystemMeasurement {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$LocalModDir,
    [Parameter(Mandatory)][string]$SourceRepoRoot,
    [string]$TrustClass = "protected-release",
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $repo
  $source = Assert-MIRCPExecutionSource -State $state -SourceRepoRoot $SourceRepoRoot
  $candidate = Get-MIRCPCanonicalCandidateArchive -State $state -RepoRoot $repo
  $row = @($state.plan.tasks | Where-Object id -eq "ecosystem.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain ecosystem.measurement exactly once." }
  $factorio = Assert-MIRCPFactorioContextLock -State $state -FactorioBin $FactorioBin
  $mods = (Resolve-Path -LiteralPath $LocalModDir).Path
  $modRows = @(Get-ChildItem -LiteralPath $mods -Filter *.zip -File | Sort-Object Name | ForEach-Object {
    [pscustomobject][ordered]@{name=$_.Name;bytes=[int64]$_.Length;sha256=(Get-MIRCPSha256File -Path $_.FullName)}
  })
  if ($modRows.Count -eq 0) { throw "Ecosystem measurement requires a non-empty local mod ZIP closure." }
  $outputRoot = Join-Path $repo "build/results/control-plane-v5/ecosystem"
  & (Join-Path $source.path "scripts/Invoke-MIRReleaseTargetedGate.ps1") -FactorioBin $factorio.path `
    -FactorioLine ([string]$state.plan.target) -LocalModDir $mods -OutputRoot $outputRoot `
    -CandidateZip $candidate -CandidateSourceCommit ([string]$source.commit) `
    -SkipBuild -SkipCleanGitStatus -SkipStrictGate -NoGitPull
  $exitCode = $LASTEXITCODE
  $summaryPath = Join-Path $outputRoot "release-targeted-summary.json"
  $summary = if (Test-Path -LiteralPath $summaryPath -PathType Leaf) { Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json } else { $null }
  $failedSteps = if ($null -eq $summary) { 1 } else { @($summary.results | Where-Object status -ne "passed").Count }
  $status = if ($exitCode -eq 0 -and $null -ne $summary -and $failedSteps -eq 0 -and [string]::IsNullOrWhiteSpace([string]$summary.failure_message)) { "passed" } else { "failed" }
  $facts = [pscustomobject][ordered]@{
    status = $status
    factorio_installation_sha256 = [string]$factorio.installation_sha256
    factorio_binary_sha256 = [string]$factorio.binary.sha256
    mod_zip_count = $modRows.Count
    mod_closure_sha256 = Get-MIRCPSha256Object -Value $modRows
    steps = if ($null -eq $summary) { 0 } else { @($summary.results).Count }
    failed_steps = $failedSteps
  }
  return Write-MIRCPSpecializedTaskEvidence -State $state -PlanRow $row[0] -ObservationKind engine-realization -Status $status `
    -EnvironmentMaterial ([pscustomobject][ordered]@{task=[string]$row[0].effective_input_sha256;factorio=$factorio;mod_closure=$modRows;source_commit=[string]$source.commit}) `
    -Facts $facts -ArtifactPath $summaryPath -ArtifactKind "ecosystem-summary" -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
}
