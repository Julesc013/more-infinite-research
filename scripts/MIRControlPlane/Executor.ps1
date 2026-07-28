function Get-MIRCPContextExecutionState {
  param([Parameter(Mandatory)][string]$ContextPath)
  $context = Assert-MIRCPVerificationContext -Path $ContextPath
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $context.path "context-manifest.json") | ConvertFrom-Json
  $planEnvelope = Get-Content -Raw -LiteralPath (Join-Path $context.path "plan.json") | ConvertFrom-Json
  if ([string]$planEnvelope.plan_id -ne [string]$manifest.plan_id) { throw "Context plan does not match its manifest." }
  return [pscustomobject][ordered]@{context=$context; manifest=$manifest; plan_envelope=$planEnvelope; plan=$planEnvelope.plan}
}

function New-MIRCPExecutorProducer {
  param([Parameter(Mandatory)][string]$TrustClass)
  return [pscustomobject][ordered]@{
    component = "mir-control-plane-v5-executor"
    abi = 1
    trust_class = $TrustClass
    repository = [string]$env:GITHUB_REPOSITORY
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
  $producer = New-MIRCPExecutorProducer -TrustClass $TrustClass
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
  $start.WorkingDirectory = $repo
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $start.CreateNoWindow = $true
  $contextAbsolute = [string]$state.context.path
  $sourceAbsolute = if ([string]::IsNullOrWhiteSpace($SourceRepoRoot)) { "" } else { (Resolve-Path -LiteralPath $SourceRepoRoot).Path }
  foreach ($argument in @($task.command.arguments)) {
    $value = [string]$argument
    if ($value -eq "<context>") { $value = $contextAbsolute }
    if ($value -eq "<source-repo>") {
      if ([string]::IsNullOrWhiteSpace($sourceAbsolute)) { throw "TaskNode $TaskId requires an exact source checkout." }
      $value = $sourceAbsolute
    }
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

function Invoke-MIRCPEnvironmentBatch {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$BatchId,
    [Parameter(Mandatory)][string]$FactorioBin,
    [string]$TrustClass = "protected-release",
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $registry = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "expanded-scenarios.json") | ConvertFrom-Json
  $batch = @($registry.batches | Where-Object id -eq $BatchId)
  if ($batch.Count -ne 1 -or -not [bool]$batch[0].process_required) { throw "Unknown or non-Factorio environment batch: $BatchId" }
  $scenarios = @($registry.scenarios | Where-Object { [string]$_.id -in @($batch[0].scenario_ids) })
  if ($scenarios.Count -ne 1) { throw "Current scenario worker supports one scenario per exact environment; registry batch $BatchId has $($scenarios.Count)." }
  $summaryRoot = Join-Path $repo "out/control-plane-v5/environment-results"
  if (-not (Test-Path -LiteralPath $summaryRoot -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $summaryRoot) }
  $summaryPath = Join-Path $summaryRoot "$([string]$batch[0].environment_signature).json"
  & (Join-Path $repo "scripts/Invoke-MIRValidation.ps1") -ScenarioWorker -FactorioBin $FactorioBin -CandidateZip (Join-Path $state.context.path "candidate.zip") -Scenario ([string]$scenarios[0].name) -ValidationSummaryPath $summaryPath
  $exitCode = $LASTEXITCODE
  if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Environment batch produced no structured validation summary: $BatchId" }
  $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
  $scenarioSummary = @($summary.scenarios | Where-Object name -eq [string]$scenarios[0].name)
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
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $row = @($state.plan.tasks | Where-Object id -eq "performance.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain performance.measurement exactly once." }
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $profile = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "target-profile.json") | ConvertFrom-Json
  $outputPath = Join-Path $repo "out/control-plane-v5/performance-evidence.json"
  $arguments = @{
    RepoRoot = $repo
    Candidate = (Join-Path $state.context.path "candidate.zip")
    PriorRelease = $PriorRelease
    FactorioBin = $FactorioBin
    ExpectedSourceCommit = [string]$descriptor.source_commit
    ExpectedBaselineVersion = [string]$profile.upgrade.from_version
    ExpectedFactorioVersion = [string]$profile.qualification_factorio_version
    OutputPath = $outputPath
  }
  if (-not [string]::IsNullOrWhiteSpace($LocalModZipDir)) { $arguments.LocalModZipDir = $LocalModZipDir }
  & (Join-Path $repo "scripts/Invoke-MIRPerformanceQualification.ps1") @arguments
  $exitCode = $LASTEXITCODE
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw "Performance measurement produced no compact evidence." }
  $status = if ($exitCode -eq 0) { "passed" } else { "failed" }
  $marker = Write-MIRCPTaskResultEvidence -State $state -PlanRow $row[0] -Status $status `
    -Payload ([pscustomobject][ordered]@{exit_code=[int]$exitCode; performance_evidence_sha256=(Get-MIRCPSha256File -Path $outputPath); performance_evidence_bytes=(Get-Item $outputPath).Length}) `
    -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
  if ($status -ne "passed") { throw "Fresh runtime performance measurement failed." }
  return $marker
}

function Complete-MIRCPAggregateGate {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [string]$TrustClass = "protected-release",
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $indexResult = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot
  if ([int]$indexResult.invalid -ne 0) { throw "Evidence store contains invalid objects." }
  $objects = @($indexResult.index.objects)
  $taskResults = [Collections.Generic.List[object]]::new()
  foreach ($row in @($state.plan.tasks | Where-Object kind -ne "aggregate")) {
    $matches = @($objects | Where-Object { [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq [string]$row.id -and [string]$_.identity_key -eq [string]$row.effective_input_sha256 -and [string]$_.status -eq "passed" -and -not [bool]$_.revoked })
    if ([string]$row.action -ne "REUSE") { $matches = @($matches | Where-Object context_digest -eq [string]$state.context.context_id) }
    if ($matches.Count -eq 0) { throw "Aggregate gate lacks exact passing evidence for TaskNode $($row.id)." }
    $taskResults.Add([pscustomobject][ordered]@{task_id=[string]$row.id;status="passed";object_digest=[string]$matches[0].digest})
  }
  $registry = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "expanded-scenarios.json") | ConvertFrom-Json
  foreach ($batch in @($registry.batches | Where-Object process_required)) {
    $matches = @($objects | Where-Object { [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq [string]$batch.id -and [string]$_.context_digest -eq [string]$state.context.context_id -and [string]$_.status -eq "passed" -and -not [bool]$_.revoked })
    if ($matches.Count -eq 1) { $taskResults.Add([pscustomobject][ordered]@{task_id=[string]$batch.id;status="passed";object_digest=[string]$matches[0].digest}) }
    elseif ($matches.Count -eq 0) { throw "Aggregate gate lacks exact passing evidence for environment batch $($batch.id)." }
    else { throw "Aggregate gate found ambiguous evidence for environment batch $($batch.id)." }
  }
  $producer = New-MIRCPExecutorProducer -TrustClass $TrustClass
  $manifest = New-MIRCPExecutionManifest -ContextDigest ([string]$state.context.context_id) -PlanId ([string]$state.plan_envelope.plan_id) -Producer $producer -TaskResults @($taskResults) -Status passed
  $manifestObject = New-MIRCPEvidenceObject -Kind execution-manifest -ContextDigest ([string]$state.context.context_id) -IdentityKey (Get-MIRCPSha256Object -Value $manifest) `
    -Subject ([pscustomobject][ordered]@{plan_id=[string]$state.plan_envelope.plan_id;target=[string]$state.plan.target}) -Producer $producer -Payload $manifest -Links @($taskResults.object_digest)
  $stored = Write-MIRCPEvidenceObject -Object $manifestObject -RepoRoot $repo -Root $EvidenceRoot
  return [pscustomobject][ordered]@{status="passed";context_digest=[string]$state.context.context_id;plan_id=[string]$state.plan_envelope.plan_id;task_results=$taskResults.Count;manifest_object=[string]$stored.digest}
}
