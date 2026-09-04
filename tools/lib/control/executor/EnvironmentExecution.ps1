function Assert-MIRCPFactorioContextLock {
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)][string]$FactorioBin
  )
  $locksRecord = Get-Content -Raw -LiteralPath (Join-Path $State.context.path "environment-locks.json") | ConvertFrom-Json
  $locks = @($locksRecord.factorio)
  if ($locks.Count -eq 0) { throw "Verification context contains no governed Factorio installation lock." }
  $identity = Get-MIRCPFactorioIdentity -FactorioBin $FactorioBin
  foreach ($lock in $locks) {
    if (Test-MIRCPFactorioIdentityMatchesLock -Identity $identity -Lock $lock) { return $identity }
  }
  throw "Factorio installation does not match any exact context lock: version=$($identity.version), binary=$($identity.binary.sha256), official-data=$($identity.official_data.sha256)."
}

function Write-MIRCPSpecializedTaskEvidence {
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)]$PlanRow,
    [Parameter(Mandatory)][ValidateSet("environment-capture", "engine-realization")][string]$ObservationKind,
    [Parameter(Mandatory)][ValidateSet("passed", "failed")][string]$Status,
    [Parameter(Mandatory)]$EnvironmentMaterial,
    [Parameter(Mandatory)]$Facts,
    [Parameter(Mandatory)][string]$ArtifactPath,
    [Parameter(Mandatory)][string]$ArtifactKind,
    [Parameter(Mandatory)][string]$TrustClass,
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
    throw "TaskNode $($PlanRow.id) produced no $ArtifactKind artifact."
  }
  $producer = New-MIRCPExecutorProducer -TrustClass $TrustClass -RepoRoot $repo
  $environmentSignature = Get-MIRCPSha256Object -Value $EnvironmentMaterial
  $artifact = [pscustomobject][ordered]@{
    kind = $ArtifactKind
    sha256 = Get-MIRCPSha256File -Path $ArtifactPath
    bytes = [int64](Get-Item -LiteralPath $ArtifactPath).Length
  }
  $source = [pscustomobject][ordered]@{
    context_digest = [string]$State.context.context_id
    task_id = [string]$PlanRow.id
    effective_input_sha256 = [string]$PlanRow.effective_input_sha256
  }
  $observation = New-MIRCPObservation -Kind $ObservationKind -EnvironmentSignature $environmentSignature `
    -Target ([string]$State.plan.target) -CandidateSha256 ([string]$State.plan.candidate_sha256) `
    -Facts $Facts -Artifacts @($artifact) -Source $source
  $observationObject = New-MIRCPEvidenceObject -Kind observation -ContextDigest ([string]$State.context.context_id) `
    -IdentityKey ([string]$observation.capture_key) -Subject ([pscustomobject][ordered]@{task_id=[string]$PlanRow.id;target=[string]$State.plan.target}) `
    -Producer $producer -Payload $observation
  $storedObservation = Write-MIRCPEvidenceObject -Object $observationObject -RepoRoot $repo -Root $EvidenceRoot
  $assertionIdPart = ([string]$PlanRow.id).ToLowerInvariant() -replace '[^a-z0-9/-]+', '-'
  $assertion = [pscustomobject][ordered]@{
    schema = 1
    id = "assertion/$assertionIdPart/status-passed"
    version = 1
    type = "status-equals"
    reads = @("facts.status")
    proposition = "TaskNode $($PlanRow.id) captured a passing native observation."
    expected = "passed"
  }
  $evaluation = Invoke-MIRCPEvaluation -Observation $observation -Assertion $assertion
  $evaluationObject = New-MIRCPEvidenceObject -Kind evaluation -ContextDigest ([string]$State.context.context_id) `
    -IdentityKey ([string]$evaluation.evaluation_key) -Subject ([pscustomobject][ordered]@{task_id=[string]$PlanRow.id;assertion_id=[string]$assertion.id;target=[string]$State.plan.target}) `
    -Producer $producer -Payload $evaluation -Links @([string]$storedObservation.digest)
  $storedEvaluation = Write-MIRCPEvidenceObject -Object $evaluationObject -RepoRoot $repo -Root $EvidenceRoot
  $taskStatus = if ($Status -eq "passed" -and [string]$evaluation.status -eq "passed") { "passed" } else { "failed" }
  $taskObject = New-MIRCPEvidenceObject -Kind task-result -ContextDigest ([string]$State.context.context_id) `
    -IdentityKey ([string]$PlanRow.effective_input_sha256) -Subject ([pscustomobject][ordered]@{task_id=[string]$PlanRow.id;target=[string]$State.plan.target;release=[string]$State.plan.release}) `
    -Producer $producer -Payload ([pscustomobject][ordered]@{
      status = $taskStatus
      effective_input_sha256 = [string]$PlanRow.effective_input_sha256
      observation_object = [string]$storedObservation.digest
      evaluation_objects = @([string]$storedEvaluation.digest)
      artifact = $artifact
    }) -Links @([string]$storedObservation.digest, [string]$storedEvaluation.digest)
  $storedTask = Write-MIRCPEvidenceObject -Object $taskObject -RepoRoot $repo -Root $EvidenceRoot
  $marker = [pscustomobject][ordered]@{
    schema = 1
    task_id = [string]$PlanRow.id
    status = $taskStatus
    context_digest = [string]$State.context.context_id
    identity_key = [string]$PlanRow.effective_input_sha256
    object_digest = [string]$storedTask.digest
  }
  [void](Write-MIRCPResultMarker -Marker $marker -RepoRoot $repo)
  if ($taskStatus -ne "passed") { throw "TaskNode $($PlanRow.id) native observation evaluated as $taskStatus." }
  return $marker
}

function Invoke-MIRCPEnvironmentBatch {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$BatchId,
    [Parameter(Mandatory)][string]$FactorioBin,
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
  $registry = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "expanded-scenarios.json") | ConvertFrom-Json
  $batch = @($registry.batches | Where-Object id -eq $BatchId)
  if ($batch.Count -ne 1 -or -not [bool]$batch[0].process_required) { throw "Unknown or non-Factorio environment batch: $BatchId" }
  $scenarios = @($registry.scenarios | Where-Object { [string]$_.id -in @($batch[0].scenario_ids) })
  if ($scenarios.Count -ne 1) { throw "Current scenario worker supports one scenario per exact environment; registry batch $BatchId has $($scenarios.Count)." }
  $summaryRoot = Join-Path $repo "build/results/control-plane-v5/environment-results"
  if (-not (Test-Path -LiteralPath $summaryRoot -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $summaryRoot) }
  $summaryPath = Join-Path $summaryRoot "$([string]$batch[0].environment_signature).json"
  & (Join-Path $source.path "scripts/Invoke-MIRValidation.ps1") -ScenarioWorker -FactorioBin $FactorioBin -CandidateZip $candidate -Scenario ([string]$scenarios[0].name) -ValidationSummaryPath $summaryPath
  $exitCode = $LASTEXITCODE
  if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Environment batch produced no structured validation summary: $BatchId" }
  $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
  $scenarioSummary = @($summary.scenarios | Where-Object { [string]$_.name -eq [string]$scenarios[0].name })
  if ($scenarioSummary.Count -ne 1) { throw "Environment summary does not contain its declared scenario." }
  $assertionFacts = [ordered]@{}
  foreach ($assertion in @($scenarios[0].assertions)) {
    $sourceId = ([string]@($assertion.reads)[0] -split '\.')[2]
    $assertionFacts[$sourceId] = [pscustomobject][ordered]@{status=if ([string]$scenarioSummary[0].status -eq "passed" -and [int]$scenarioSummary[0].assertions_executed -ge @($scenarios[0].assertions).Count) { "passed" } else { "failed" }}
  }
  $facts = [pscustomobject][ordered]@{
    status = [string]$summary.status
    factorio_binary_version = [string]$summary.factorio_binary_version
    factorio_binary_sha256 = [string]$factorio.binary.sha256
    factorio_official_data_sha256 = [string]$factorio.official_data.sha256
    candidate_sha256 = [string]$summary.validation_package_sha256
    candidate_content_sha256 = [string]$summary.validation_package_content_sha256
    validation_harness_sha256 = [string]$summary.validation_harness_sha256
    target_profile_sha256 = [string]$summary.target_profile_sha256
    scenario = [pscustomobject][ordered]@{name=[string]$scenarioSummary[0].name; kind=[string]$scenarioSummary[0].kind; group=[string]$scenarioSummary[0].group; status=[string]$scenarioSummary[0].status; assertions_executed=[int]$scenarioSummary[0].assertions_executed}
    assertions = [pscustomobject]$assertionFacts
  }
  $observation = New-MIRCPObservation -Kind engine-realization -EnvironmentSignature ([string]$batch[0].environment_signature) -Target ([string]$state.plan.target) `
    -CandidateSha256 ([string]$state.plan.candidate_sha256) -Facts $facts -Artifacts @([pscustomobject][ordered]@{kind="validation-summary"; sha256=(Get-MIRCPSha256File -Path $summaryPath); bytes=(Get-Item $summaryPath).Length}) `
    -Source ([pscustomobject][ordered]@{context_digest=[string]$state.context.context_id; batch_id=$BatchId})
  $producer = New-MIRCPExecutorProducer -TrustClass $TrustClass -RepoRoot $repo
  $observationObject = New-MIRCPEvidenceObject -Kind observation -ContextDigest ([string]$state.context.context_id) -IdentityKey ([string]$observation.capture_key) `
    -Subject ([pscustomobject][ordered]@{task_id=$BatchId; target=[string]$state.plan.target}) -Producer $producer -Payload $observation
  $storedObservation = Write-MIRCPEvidenceObject -Object $observationObject -RepoRoot $repo -Root $EvidenceRoot
  $evaluationDigests = [Collections.Generic.List[string]]::new()
  $statuses = [Collections.Generic.List[string]]::new()
  foreach ($assertion in @($scenarios[0].assertions)) {
    $evaluation = Invoke-MIRCPEvaluation -Observation $observation -Assertion $assertion
    $evaluationObject = New-MIRCPEvidenceObject -Kind evaluation -ContextDigest ([string]$state.context.context_id) -IdentityKey ([string]$evaluation.evaluation_key) `
      -Subject ([pscustomobject][ordered]@{task_id=$BatchId; assertion_id=[string]$assertion.id; target=[string]$state.plan.target}) -Producer $producer -Payload $evaluation -Links @([string]$storedObservation.digest)
    $storedEvaluation = Write-MIRCPEvidenceObject -Object $evaluationObject -RepoRoot $repo -Root $EvidenceRoot
    $evaluationDigests.Add([string]$storedEvaluation.digest)
    $statuses.Add([string]$evaluation.status)
  }
  $status = if ($exitCode -eq 0 -and @($statuses | Where-Object { $_ -ne "passed" }).Count -eq 0) { "passed" } else { "failed" }
  $batchIdentity = Get-MIRCPSha256Object -Value ([pscustomobject][ordered]@{context=[string]$state.context.context_id; batch=$batch[0]})
  $links = @([string]$storedObservation.digest) + @($evaluationDigests)
  $taskObject = New-MIRCPEvidenceObject -Kind task-result -ContextDigest ([string]$state.context.context_id) -IdentityKey $batchIdentity `
    -Subject ([pscustomobject][ordered]@{task_id=$BatchId; target=[string]$state.plan.target}) -Producer $producer `
    -Payload ([pscustomobject][ordered]@{status=$status; environment_signature=[string]$batch[0].environment_signature; observation_object=[string]$storedObservation.digest; evaluation_objects=@($evaluationDigests)}) `
    -Links $links
  $storedTask = Write-MIRCPEvidenceObject -Object $taskObject -RepoRoot $repo -Root $EvidenceRoot
  [void](Write-MIRCPResultMarker -Marker ([pscustomobject][ordered]@{schema=1;task_id=$BatchId;status=$status;context_digest=[string]$state.context.context_id;identity_key=$batchIdentity;object_digest=[string]$storedTask.digest}) -RepoRoot $repo)
  if ($status -ne "passed") { throw "Environment batch failed: $BatchId" }
  return [pscustomobject][ordered]@{batch_id=$BatchId; status=$status; object_digest=[string]$storedTask.digest; evaluations=$evaluationDigests.Count}
}
