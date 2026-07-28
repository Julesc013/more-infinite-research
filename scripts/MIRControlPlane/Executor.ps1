function Get-MIRCPContextExecutionState {
  param([Parameter(Mandatory)][string]$ContextPath)
  $context = Assert-MIRCPVerificationContext -Path $ContextPath
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $context.path "context-manifest.json") | ConvertFrom-Json
  $planEnvelope = Get-Content -Raw -LiteralPath (Join-Path $context.path "plan.json") | ConvertFrom-Json
  if ([string]$planEnvelope.plan_id -ne [string]$manifest.plan_id) { throw "Context plan does not match its manifest." }
  return [pscustomobject][ordered]@{context=$context; manifest=$manifest; plan_envelope=$planEnvelope; plan=$planEnvelope.plan}
}

function Assert-MIRCPProtectedExecutionEnvironment {
  param([string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $policy = Read-MIRCPJson -Path "validation/trust.json" -RepoRoot $repo
  $class = $policy.classes.'protected-release'
  $checks = [ordered]@{
    repository = [string]$env:GITHUB_REPOSITORY
    workflow = [string]$env:GITHUB_WORKFLOW
    event = [string]$env:GITHUB_EVENT_NAME
    ref = [string]$env:GITHUB_REF
    environment = [string]$env:MIR_PROTECTED_ENVIRONMENT
    runner_identity = [string]$env:MIR_TRUSTED_RUNNER
    runner_environment = [string]$env:RUNNER_ENVIRONMENT
  }
  foreach ($field in @("repository", "workflow", "event", "ref")) {
    $plural = @{repository="repositories";workflow="workflows";event="events";ref="refs"}[$field]
    if (@($class.$plural | ForEach-Object { [string]$_ }) -notcontains [string]$checks[$field]) { throw "Protected-release producer has untrusted $field identity." }
  }
  foreach ($field in @("environment", "runner_identity", "runner_environment")) {
    if ([string]$checks[$field] -ne [string]$class.$field) { throw "Protected-release producer has untrusted $field identity." }
  }
  foreach ($field in @("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_JOB", "RUNNER_NAME")) {
    if ([string]::IsNullOrWhiteSpace([string][Environment]::GetEnvironmentVariable($field))) { throw "Protected-release producer is missing $field." }
  }
  $tracked = @(& git -C $repo status --porcelain --untracked-files=no)
  if ($LASTEXITCODE -ne 0 -or $tracked.Count -ne 0) { throw "Protected-release producer control-plane checkout is not clean." }
  return [pscustomobject]$checks
}

function New-MIRCPExecutorProducer {
  param([Parameter(Mandatory)][string]$TrustClass, [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  if ($TrustClass -eq "protected-release") { [void](Assert-MIRCPProtectedExecutionEnvironment -RepoRoot $repo) }
  return [pscustomobject][ordered]@{
    component = "mir-control-plane-v5-executor"
    abi = 1
    trust_class = $TrustClass
    repository = [string]$env:GITHUB_REPOSITORY
    workflow = [string]$env:GITHUB_WORKFLOW
    event = [string]$env:GITHUB_EVENT_NAME
    ref = [string]$env:GITHUB_REF
    environment = [string]$env:MIR_PROTECTED_ENVIRONMENT
    runner_identity = [string]$env:MIR_TRUSTED_RUNNER
    runner_environment = [string]$env:RUNNER_ENVIRONMENT
    commit = ([string](& git -C $repo rev-parse HEAD)).Trim()
    trust_policy_sha256 = Get-MIRCPSha256File -Path (Join-Path $repo "validation/trust.json")
    run_id = [string]$env:GITHUB_RUN_ID
    run_attempt = [string]$env:GITHUB_RUN_ATTEMPT
    job = [string]$env:GITHUB_JOB
    runner = [string]$env:RUNNER_NAME
    produced_at = [datetimeoffset]::UtcNow.ToString("o")
  }
}

function Write-MIRCPResultMarker {
  param(
    [Parameter(Mandatory)]$Marker,
    [Parameter(Mandatory)][string]$RepoRoot
  )
  $safe = ([string]$Marker.task_id) -replace '[^A-Za-z0-9_.-]+', '_'
  $path = Join-Path $RepoRoot "out/control-plane-v5/results/$safe.json"
  Write-MIRCPJson -Path $path -Value $Marker -RepoRoot $RepoRoot
  return $path
}

function Write-MIRCPTaskResultEvidence {
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)]$PlanRow,
    [Parameter(Mandatory)][string]$Status,
    [Parameter(Mandatory)]$Payload,
    [Parameter(Mandatory)][string]$TrustClass,
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $producer = New-MIRCPExecutorProducer -TrustClass $TrustClass -RepoRoot $RepoRoot
  if ($TrustClass -eq "protected-release") {
    $controlLock = Get-Content -Raw -LiteralPath (Join-Path $State.context.path "control-plane-lock.json") | ConvertFrom-Json
    if ([string]$producer.commit -ne [string]$controlLock.qualification_source_commit) { throw "Protected-release producer commit differs from the immutable context control-plane lock." }
  }
  $fullPayload = [ordered]@{status=$Status; effective_input_sha256=[string]$PlanRow.effective_input_sha256}
  foreach ($property in $Payload.PSObject.Properties) { $fullPayload[$property.Name] = $property.Value }
  $object = New-MIRCPEvidenceObject -Kind task-result -ContextDigest ([string]$State.context.context_id) -IdentityKey ([string]$PlanRow.effective_input_sha256) `
    -Subject ([pscustomobject][ordered]@{task_id=[string]$PlanRow.id; target=[string]$State.plan.target; release=[string]$State.plan.release}) `
    -Producer $producer -Payload ([pscustomobject]$fullPayload)
  $stored = Write-MIRCPEvidenceObject -Object $object -RepoRoot $RepoRoot -Root $EvidenceRoot
  $marker = [pscustomobject][ordered]@{schema=1; task_id=[string]$PlanRow.id; status=$Status; context_digest=[string]$State.context.context_id; identity_key=[string]$PlanRow.effective_input_sha256; object_digest=[string]$stored.digest}
  [void](Write-MIRCPResultMarker -Marker $marker -RepoRoot (Get-MIRCPRepoRoot -RepoRoot $RepoRoot))
  return $marker
}

function Write-MIRCPContextCompletionEvidence {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [string]$TrustClass = "ci",
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $row = @($state.plan.tasks | Where-Object id -eq "verification.context")
  if ($row.Count -ne 1) { throw "Context plan does not contain verification.context exactly once." }
  return Write-MIRCPTaskResultEvidence -State $state -PlanRow $row[0] -Status passed `
    -Payload ([pscustomobject][ordered]@{members=[int]$state.context.members; verified_context_digest=[string]$state.context.context_id}) `
    -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $RepoRoot
}

function Invoke-MIRCPTaskCommand {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$TaskId,
    [string]$TrustClass = "ci",
    [string]$EvidenceRoot = "",
    [int]$TimeoutSeconds = 3600,
    [string]$SourceRepoRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $row = @($state.plan.tasks | Where-Object id -eq $TaskId)
  if ($row.Count -ne 1) { throw "Context plan does not contain TaskNode $TaskId exactly once." }
  if ([string]$row[0].kind -eq "aggregate") { throw "Aggregate TaskNode $TaskId cannot execute a command." }
  if ([string]$row[0].action -eq "REUSE") { return [pscustomobject][ordered]@{task_id=$TaskId; status="reused"; object_digest=[string]$row[0].evidence_decision.object_digest} }
  $task = (Get-MIRCPTaskMap -RepoRoot $repo)[$TaskId]
  $process = [Diagnostics.Process]::new()
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = Join-Path $PSHOME "pwsh.exe"
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $start.CreateNoWindow = $true
  $contextAbsolute = [string]$state.context.path
  $sourceAbsolute = if ([string]::IsNullOrWhiteSpace($SourceRepoRoot)) { "" } else { (Resolve-Path -LiteralPath $SourceRepoRoot).Path }
  $commandScope = if ($null -eq $task.PSObject.Properties["command_scope"]) { "control-plane" } else { [string]$task.command_scope }
  if ($commandScope -eq "source" -and [string]::IsNullOrWhiteSpace($sourceAbsolute)) { throw "TaskNode $TaskId requires an exact source checkout." }
  $start.WorkingDirectory = if ($commandScope -eq "source") { $sourceAbsolute } else { $repo }
  foreach ($argument in @($task.command.arguments)) {
    $value = [string]$argument
    if ($value -eq "<context>") { $value = $contextAbsolute }
    if ($value -eq "<source-repo>") {
      if ([string]::IsNullOrWhiteSpace($sourceAbsolute)) { throw "TaskNode $TaskId requires an exact source checkout." }
      $value = $sourceAbsolute
    }
    if ($value -eq "<evidence-root>") { $value = Get-MIRCPEvidenceRoot -RepoRoot $repo -Root $EvidenceRoot }
    [void]$start.ArgumentList.Add($value)
  }
  $process.StartInfo = $start
  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    try { $process.Kill($true) } catch {}
    throw "TaskNode $TaskId exceeded $TimeoutSeconds seconds."
  }
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  if (-not [string]::IsNullOrWhiteSpace($stdout)) { Write-Host $stdout.TrimEnd() }
  if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Warning $stderr.TrimEnd() }
  $status = if ($process.ExitCode -eq 0) { "passed" } else { "failed" }
  $marker = Write-MIRCPTaskResultEvidence -State $state -PlanRow $row[0] -Status $status `
    -Payload ([pscustomobject][ordered]@{exit_code=[int]$process.ExitCode; stdout_sha256=(Get-MIRCPSha256Text -Value $stdout); stderr_sha256=(Get-MIRCPSha256Text -Value $stderr)}) `
    -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
  if ($process.ExitCode -ne 0) { throw "TaskNode $TaskId failed with exit code $($process.ExitCode)." }
  return $marker
}

function Invoke-MIRCPTaskSet {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string[]]$Kind,
    [string[]]$ExcludeTask = @(),
    [string]$TrustClass = "ci",
    [string]$EvidenceRoot = "",
    [string]$SourceRepoRoot = "",
    [string]$RepoRoot = ""
  )
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $rows = @($state.plan.tasks | Where-Object { [string]$_.kind -in $Kind -and [string]$_.kind -ne "aggregate" -and [string]$_.id -notin $ExcludeTask })
  $completed = [Collections.Generic.List[object]]::new()
  foreach ($row in $rows) {
    $completed.Add((Invoke-MIRCPTaskCommand -ContextPath $ContextPath -TaskId ([string]$row.id) -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -SourceRepoRoot $SourceRepoRoot -RepoRoot $RepoRoot))
  }
  return @($completed)
}

function Assert-MIRCPExecutionSource {
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)][string]$SourceRepoRoot
  )
  if ([string]::IsNullOrWhiteSpace($SourceRepoRoot)) { throw "This worker requires an immutable qualification-source checkout." }
  $source = (Resolve-Path -LiteralPath $SourceRepoRoot).Path
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $State.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $controlLock = Get-Content -Raw -LiteralPath (Join-Path $State.context.path "control-plane-lock.json") | ConvertFrom-Json
  $head = ([string](& git -C $source rev-parse HEAD)).Trim()
  $tree = ([string](& git -C $source rev-parse "HEAD^{tree}")).Trim()
  $worktreeSha256 = Get-MIRCPTrackedWorktreeSha256 -SourceRepoRoot $source
  if ($LASTEXITCODE -ne 0 -or $head -ne [string]$controlLock.scenario_source_commit -or $tree -ne [string]$controlLock.scenario_source_tree -or
      $worktreeSha256 -ne [string]$controlLock.scenario_source_worktree_sha256) {
    throw "Execution source does not match the immutable context qualification-source lock."
  }
  return [pscustomobject][ordered]@{path=$source;descriptor=$descriptor;commit=$head;tree=$tree;worktree_sha256=$worktreeSha256}
}

function Get-MIRCPFactorioIdentity {
  param([Parameter(Mandatory)][string]$FactorioBin)
  $binary = (Resolve-Path -LiteralPath $FactorioBin).Path
  $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($binary).FileVersion
  return [pscustomobject][ordered]@{
    path = $binary
    sha256 = Get-MIRCPSha256File -Path $binary
    bytes = [int64](Get-Item -LiteralPath $binary).Length
    version = [string]$version
  }
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
  $producer = New-MIRCPExecutorProducer -TrustClass $TrustClass
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
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $source = Assert-MIRCPExecutionSource -State $state -SourceRepoRoot $SourceRepoRoot
  $registry = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "expanded-scenarios.json") | ConvertFrom-Json
  $batch = @($registry.batches | Where-Object id -eq $BatchId)
  if ($batch.Count -ne 1 -or -not [bool]$batch[0].process_required) { throw "Unknown or non-Factorio environment batch: $BatchId" }
  $scenarios = @($registry.scenarios | Where-Object { [string]$_.id -in @($batch[0].scenario_ids) })
  if ($scenarios.Count -ne 1) { throw "Current scenario worker supports one scenario per exact environment; registry batch $BatchId has $($scenarios.Count)." }
  $summaryRoot = Join-Path $repo "out/control-plane-v5/environment-results"
  if (-not (Test-Path -LiteralPath $summaryRoot -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $summaryRoot) }
  $summaryPath = Join-Path $summaryRoot "$([string]$batch[0].environment_signature).json"
  & (Join-Path $source.path "scripts/Invoke-MIRValidation.ps1") -ScenarioWorker -FactorioBin $FactorioBin -CandidateZip (Join-Path $state.context.path "candidate.zip") -Scenario ([string]$scenarios[0].name) -ValidationSummaryPath $summaryPath
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
  $producer = New-MIRCPExecutorProducer -TrustClass $TrustClass
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
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $source = Assert-MIRCPExecutionSource -State $state -SourceRepoRoot $SourceRepoRoot
  $row = @($state.plan.tasks | Where-Object id -eq "performance.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain performance.measurement exactly once." }
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $profile = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "target-profile.json") | ConvertFrom-Json
  $outputPath = Join-Path $repo "out/control-plane-v5/performance-evidence.json"
  $arguments = @{
    RepoRoot = $source.path
    Candidate = (Join-Path $state.context.path "candidate.zip")
    PriorRelease = $PriorRelease
    FactorioBin = $FactorioBin
    ExpectedSourceCommit = [string]$descriptor.source_commit
    ExpectedBaselineVersion = [string]$profile.upgrade.from_version
    ExpectedFactorioVersion = [string]$profile.qualification_factorio_version
    OutputPath = $outputPath
  }
  if (-not [string]::IsNullOrWhiteSpace($LocalModZipDir)) { $arguments.LocalModZipDir = $LocalModZipDir }
  & (Join-Path $source.path "scripts/Invoke-MIRPerformanceQualification.ps1") @arguments
  $exitCode = $LASTEXITCODE
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw "Performance measurement produced no compact evidence." }
  $status = if ($exitCode -eq 0) { "passed" } else { "failed" }
  $marker = Write-MIRCPTaskResultEvidence -State $state -PlanRow $row[0] -Status $status `
    -Payload ([pscustomobject][ordered]@{exit_code=[int]$exitCode; performance_evidence_sha256=(Get-MIRCPSha256File -Path $outputPath); performance_evidence_bytes=(Get-Item $outputPath).Length}) `
    -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
  if ($status -ne "passed") { throw "Fresh runtime performance measurement failed." }
  return $marker
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
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $source = Assert-MIRCPExecutionSource -State $state -SourceRepoRoot $SourceRepoRoot
  $row = @($state.plan.tasks | Where-Object id -eq "upgrade.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain upgrade.measurement exactly once." }
  $profile = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "target-profile.json") | ConvertFrom-Json
  $factorio = Get-MIRCPFactorioIdentity -FactorioBin $FactorioBin
  $prior = (Resolve-Path -LiteralPath $PriorRelease).Path
  $outputPath = Join-Path $repo "out/control-plane-v5/upgrade-evidence.json"
  & (Join-Path $source.path "scripts/Test-MIRUpgradeMatrix.ps1") -RepoRoot $source.path `
    -FactorioBin $factorio.path -FromZip $prior -ToZip (Join-Path $state.context.path "candidate.zip") `
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
    factorio_binary_sha256 = [string]$factorio.sha256
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
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $source = Assert-MIRCPExecutionSource -State $state -SourceRepoRoot $SourceRepoRoot
  $row = @($state.plan.tasks | Where-Object id -eq "ecosystem.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain ecosystem.measurement exactly once." }
  $factorio = Get-MIRCPFactorioIdentity -FactorioBin $FactorioBin
  $mods = (Resolve-Path -LiteralPath $LocalModDir).Path
  $modRows = @(Get-ChildItem -LiteralPath $mods -Filter *.zip -File | Sort-Object Name | ForEach-Object {
    [pscustomobject][ordered]@{name=$_.Name;bytes=[int64]$_.Length;sha256=(Get-MIRCPSha256File -Path $_.FullName)}
  })
  if ($modRows.Count -eq 0) { throw "Ecosystem measurement requires a non-empty local mod ZIP closure." }
  $outputRoot = Join-Path $repo "out/control-plane-v5/ecosystem"
  & (Join-Path $source.path "scripts/Invoke-MIRReleaseTargetedGate.ps1") -FactorioBin $factorio.path `
    -FactorioLine ([string]$state.plan.target) -LocalModDir $mods -OutputRoot $outputRoot `
    -CandidateZip (Join-Path $state.context.path "candidate.zip") -CandidateSourceCommit ([string]$source.commit) `
    -SkipBuild -SkipCleanGitStatus -SkipStrictGate -NoGitPull
  $exitCode = $LASTEXITCODE
  $summaryPath = Join-Path $outputRoot "release-targeted-summary.json"
  $summary = if (Test-Path -LiteralPath $summaryPath -PathType Leaf) { Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json } else { $null }
  $failedSteps = if ($null -eq $summary) { 1 } else { @($summary.results | Where-Object status -ne "passed").Count }
  $status = if ($exitCode -eq 0 -and $null -ne $summary -and $failedSteps -eq 0 -and [string]::IsNullOrWhiteSpace([string]$summary.failure_message)) { "passed" } else { "failed" }
  $facts = [pscustomobject][ordered]@{
    status = $status
    factorio_binary_sha256 = [string]$factorio.sha256
    mod_zip_count = $modRows.Count
    mod_closure_sha256 = Get-MIRCPSha256Object -Value $modRows
    steps = if ($null -eq $summary) { 0 } else { @($summary.results).Count }
    failed_steps = $failedSteps
  }
  return Write-MIRCPSpecializedTaskEvidence -State $state -PlanRow $row[0] -ObservationKind engine-realization -Status $status `
    -EnvironmentMaterial ([pscustomobject][ordered]@{task=[string]$row[0].effective_input_sha256;factorio=$factorio;mod_closure=$modRows;source_commit=[string]$source.commit}) `
    -Facts $facts -ArtifactPath $summaryPath -ArtifactKind "ecosystem-summary" -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
}

function Invoke-MIRCPApprovedDeltaMeasurement {
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
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $source = Assert-MIRCPExecutionSource -State $state -SourceRepoRoot $SourceRepoRoot
  $row = @($state.plan.tasks | Where-Object id -eq "approved-delta.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain approved-delta.measurement exactly once." }
  $factorio = Get-MIRCPFactorioIdentity -FactorioBin $FactorioBin
  $prior = (Resolve-Path -LiteralPath $PriorRelease).Path
  $outputPath = Join-Path $repo "out/control-plane-v5/approved-delta.json"
  $rawRoot = Join-Path $repo "out/control-plane-v5/approved-delta-raw"
  & (Join-Path $source.path "scripts/Export-MIRApprovedDelta.ps1") -BaselinePackage $prior `
    -CurrentPackage (Join-Path $state.context.path "candidate.zip") -FactorioBin $factorio.path `
    -OutputPath $outputPath -EvidenceRoot $rawRoot -ExpectedBaselineSha256 (Get-MIRCPSha256File -Path $prior) `
    -ExpectedSourceCommit ([string]$source.commit)
  $exportExitCode = $LASTEXITCODE
  if ($exportExitCode -eq 0) {
    & (Join-Path $source.path "scripts/Test-MIRApprovedDelta.ps1") -Path $outputPath `
      -Candidate (Join-Path $state.context.path "candidate.zip") -ExpectedSourceCommit ([string]$source.commit)
  }
  $testExitCode = $LASTEXITCODE
  $artifact = if (Test-Path -LiteralPath $outputPath -PathType Leaf) { Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json } else { $null }
  $status = if ($exportExitCode -eq 0 -and $testExitCode -eq 0 -and $null -ne $artifact -and [string]$artifact.summary.status -eq "approved" -and [int]$artifact.summary.unapproved_count -eq 0) { "passed" } else { "failed" }
  $facts = [pscustomobject][ordered]@{
    status = $status
    factorio_binary_sha256 = [string]$factorio.sha256
    prior_archive_sha256 = Get-MIRCPSha256File -Path $prior
    difference_count = if ($null -eq $artifact) { -1 } else { [int]$artifact.summary.difference_count }
    unapproved_count = if ($null -eq $artifact) { -1 } else { [int]$artifact.summary.unapproved_count }
    artifact_status = if ($null -eq $artifact) { "missing" } else { [string]$artifact.summary.status }
  }
  return Write-MIRCPSpecializedTaskEvidence -State $state -PlanRow $row[0] -ObservationKind engine-realization -Status $status `
    -EnvironmentMaterial ([pscustomobject][ordered]@{task=[string]$row[0].effective_input_sha256;factorio=$factorio;prior_archive_sha256=$facts.prior_archive_sha256;source_commit=[string]$source.commit}) `
    -Facts $facts -ArtifactPath $outputPath -ArtifactKind "approved-delta" -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
}

function Complete-MIRCPAggregateGate {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [string]$TrustClass = "protected-release",
    [string]$AggregateTaskId = "",
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $indexResult = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot
  if ([int]$indexResult.invalid -ne 0) { throw "Evidence store contains invalid objects." }
  $objects = @($indexResult.index.objects)
  $selectedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  if ([string]::IsNullOrWhiteSpace($AggregateTaskId)) {
    foreach ($row in @($state.plan.tasks)) { [void]$selectedIds.Add([string]$row.id) }
  } else {
    $aggregateTarget = @($state.plan.tasks | Where-Object { [string]$_.id -eq $AggregateTaskId -and [string]$_.kind -eq "aggregate" })
    if ($aggregateTarget.Count -ne 1) { throw "Context plan does not contain aggregate TaskNode $AggregateTaskId exactly once." }
    [void]$selectedIds.Add($AggregateTaskId)
    $changed = $true
    while ($changed) {
      $changed = $false
      foreach ($row in @($state.plan.tasks | Where-Object { $selectedIds.Contains([string]$_.id) })) {
        foreach ($dependency in @($row.depends_on)) { if ($selectedIds.Add([string]$dependency)) { $changed = $true } }
      }
    }
  }
  $taskResults = [Collections.Generic.List[object]]::new()
  $taskMap = Get-MIRCPTaskMap -RepoRoot $repo
  foreach ($row in @($state.plan.tasks | Where-Object { [string]$_.kind -ne "aggregate" -and $selectedIds.Contains([string]$_.id) })) {
    $matches = @($objects | Where-Object { [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq [string]$row.id -and [string]$_.identity_key -eq [string]$row.effective_input_sha256 -and [string]$_.status -eq "passed" -and -not [bool]$_.revoked })
    if ([string]$row.action -ne "REUSE") { $matches = @($matches | Where-Object { [string]$_.context_digest -eq [string]$state.context.context_id }) }
    if ($TrustClass -eq "protected-release") {
      $task = $taskMap[[string]$row.id]
      if ([string]$task.kind -eq "manual") { $matches = @($matches | Where-Object trust_class -eq "ci") }
      elseif ([string]$task.freshness -in @("protected-release-fresh", "always-fresh")) { $matches = @($matches | Where-Object trust_class -eq "protected-release") }
    }
    if ($matches.Count -eq 0) { throw "Aggregate gate lacks exact passing evidence for TaskNode $($row.id)." }
    $taskResults.Add([pscustomobject][ordered]@{task_id=[string]$row.id;status="passed";object_digest=[string]$matches[0].digest})
  }
  $registry = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "expanded-scenarios.json") | ConvertFrom-Json
  $requiresEnvironmentBatches = $selectedIds.Contains("ecosystem.measurement")
  foreach ($batch in @($registry.batches | Where-Object { $requiresEnvironmentBatches -and [bool]$_.process_required })) {
    $matches = @($objects | Where-Object { [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq [string]$batch.id -and [string]$_.context_digest -eq [string]$state.context.context_id -and [string]$_.status -eq "passed" -and -not [bool]$_.revoked })
    if ($TrustClass -eq "protected-release") { $matches = @($matches | Where-Object trust_class -eq "protected-release") }
    if ($matches.Count -eq 1) { $taskResults.Add([pscustomobject][ordered]@{task_id=[string]$batch.id;status="passed";object_digest=[string]$matches[0].digest}) }
    elseif ($matches.Count -eq 0) { throw "Aggregate gate lacks exact passing evidence for environment batch $($batch.id)." }
    else { throw "Aggregate gate found ambiguous evidence for environment batch $($batch.id)." }
  }
  foreach ($row in @($state.plan.tasks | Where-Object { [string]$_.kind -eq "aggregate" -and $selectedIds.Contains([string]$_.id) })) {
    $selectedMembers = @($row.depends_on | ForEach-Object { [string]$_ })
    $missingMembers = @($selectedMembers | Where-Object { $member = $_; @($taskResults | Where-Object task_id -eq $member).Count -ne 1 })
    if ($missingMembers.Count -gt 0) { throw "Aggregate TaskNode $($row.id) lacks exact member results: $($missingMembers -join ', ')." }
    $memberResults = @($taskResults | Where-Object { [string]$_.task_id -in $selectedMembers } | Sort-Object task_id)
    $aggregateMarker = Write-MIRCPTaskResultEvidence -State $state -PlanRow $row -Status passed `
      -Payload ([pscustomobject][ordered]@{aggregate=$true;members=@($memberResults | ForEach-Object { [pscustomobject][ordered]@{task_id=[string]$_.task_id;object_digest=[string]$_.object_digest} })}) `
      -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
    $taskResults.Add($aggregateMarker)
  }
  $producer = New-MIRCPExecutorProducer -TrustClass $TrustClass -RepoRoot $repo
  $manifest = New-MIRCPExecutionManifest -ContextDigest ([string]$state.context.context_id) -PlanId ([string]$state.plan_envelope.plan_id) -Producer $producer -TaskResults @($taskResults) -Status passed
  $manifestObject = New-MIRCPEvidenceObject -Kind execution-manifest -ContextDigest ([string]$state.context.context_id) -IdentityKey (Get-MIRCPSha256Object -Value $manifest) `
    -Subject ([pscustomobject][ordered]@{plan_id=[string]$state.plan_envelope.plan_id;target=[string]$state.plan.target}) -Producer $producer -Payload $manifest -Links @($taskResults.object_digest)
  $stored = Write-MIRCPEvidenceObject -Object $manifestObject -RepoRoot $repo -Root $EvidenceRoot
  return [pscustomobject][ordered]@{status="passed";context_digest=[string]$state.context.context_id;plan_id=[string]$state.plan_envelope.plan_id;aggregate_task=if([string]::IsNullOrWhiteSpace($AggregateTaskId)){"all"}else{$AggregateTaskId};task_results=$taskResults.Count;manifest_object=[string]$stored.digest}
}
