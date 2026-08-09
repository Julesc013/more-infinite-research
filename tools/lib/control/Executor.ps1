. (Join-Path $PSScriptRoot "../validation/PerformanceCampaign.ps1")

function Get-MIRCPContextExecutionState {
  param([Parameter(Mandatory)][string]$ContextPath, [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $context = Assert-MIRCPVerificationContext -Path $ContextPath
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $context.path "context-manifest.json") | ConvertFrom-Json
  if ([int]$manifest.context_abi -ne 3) { throw "Context execution requires verification context ABI 3." }
  $planEnvelope = Get-Content -Raw -LiteralPath (Join-Path $context.path "plan.json") | ConvertFrom-Json
  if ([string]$planEnvelope.plan_id -ne [string]$manifest.plan_id) { throw "Context plan does not match its manifest." }
  $controlLock = Get-Content -Raw -LiteralPath (Join-Path $context.path "control-plane-lock.json") | ConvertFrom-Json
  $head = ([string](& git -C $repo rev-parse HEAD)).Trim()
  $untracked = @(& git -C $repo ls-files --others --exclude-standard)
  $worktreeSha256 = Get-MIRCPTrackedWorktreeSha256 -SourceRepoRoot $repo
  if ($LASTEXITCODE -ne 0 -or $untracked.Count -ne 0 -or $head -ne [string]$controlLock.qualification_source_commit -or
      $worktreeSha256 -ne [string]$controlLock.qualification_source_worktree_sha256) {
    throw "Executor checkout does not match the immutable context control-plane lock."
  }
  foreach ($file in @($controlLock.files)) {
    $path = Join-Path $repo ([string]$file.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-MIRCPSha256File -Path $path) -ne [string]$file.sha256) {
      throw "Executor control-plane file differs from the immutable context lock: $($file.path)"
    }
  }
  return [pscustomobject][ordered]@{context=$context; manifest=$manifest; plan_envelope=$planEnvelope; plan=$planEnvelope.plan; control_lock=$controlLock}
}

function Get-MIRCPCanonicalCandidateArchive {
  param([Parameter(Mandatory)]$State, [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $candidate = Join-Path $State.context.path "candidate.zip"
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $State.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $archive = [IO.Compression.ZipFile]::OpenRead($candidate)
  try {
    $infoEntries = @($archive.Entries | Where-Object { [string]$_.FullName -match '^[^/]+/info\.json$' })
    if ($infoEntries.Count -ne 1) { throw "Immutable candidate must contain exactly one root info.json." }
    $stream = $infoEntries[0].Open()
    $reader = [IO.StreamReader]::new($stream)
    try { $info = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose(); $stream.Dispose() }
  } finally {
    $archive.Dispose()
  }
  $name = [string]$info.name
  $version = [string]$info.version
  if ($name -notmatch '^[A-Za-z0-9_-]+$' -or $version -notmatch '^[0-9][A-Za-z0-9._-]*$' -or $version -ne [string]$descriptor.release) {
    throw "Immutable candidate metadata cannot produce a safe canonical Factorio archive name."
  }
  $root = Join-Path $repo "build/results/control-plane-v5/context-candidates/$([string]$State.context.context_id)"
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $root) }
  $destination = Join-Path $root "${name}_${version}.zip"
  if (Test-Path -LiteralPath $destination -PathType Leaf) {
    if ((Get-MIRCPSha256File -Path $destination) -ne [string]$descriptor.archive_sha256) { throw "Canonical candidate staging path contains different bytes." }
  } else {
    $temporary = "$destination.$([guid]::NewGuid().ToString('N')).tmp"
    Copy-Item -LiteralPath $candidate -Destination $temporary
    if ((Get-MIRCPSha256File -Path $temporary) -ne [string]$descriptor.archive_sha256) {
      [IO.File]::Delete($temporary)
      throw "Canonical candidate staging copy changed immutable bytes."
    }
    [IO.File]::Move($temporary, $destination)
  }
  return $destination
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
  $path = Join-Path $RepoRoot "build/results/control-plane-v5/results/$safe.json"
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
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $RepoRoot
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
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $repo
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
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $RepoRoot
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

function Assert-MIRCPPerformanceCampaignAuthority {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Descriptor,
    [Parameter(Mandatory)]$TargetProfile,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $campaign = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $Path) | ConvertFrom-Json
  $baseline = Get-MIRCPReleaseByVersion -Release ([string]$TargetProfile.upgrade.from_version) -RepoRoot $repo
  if ([int]$campaign.schema -ne 2 -or [string]$campaign.release -ne [string]$Descriptor.release -or
      [string]$campaign.factorio_line -ne [string]$Descriptor.target -or
      [string]$campaign.factorio_version -ne [string]$TargetProfile.qualification_factorio_version -or
      [string]$campaign.baseline.version -ne [string]$baseline.release -or
      [string]$campaign.baseline.archive_sha256 -ne [string]$baseline.package.archive_sha256 -or
      [string]$campaign.baseline.package_content_sha256 -ne [string]$baseline.package.content_sha256 -or
      [string]$campaign.candidate.candidate_id -ne [string]$Descriptor.candidate_id -or
      [string]$campaign.candidate.version -ne [string]$Descriptor.release -or
      [string]$campaign.candidate.package_source_commit -ne [string]$Descriptor.source_commit -or
      [string]$campaign.candidate.package_source_sha256 -ne [string]$Descriptor.source_sha256 -or
      [string]$campaign.candidate.archive_sha256 -ne [string]$Descriptor.archive_sha256 -or
      [string]$campaign.candidate.package_content_sha256 -ne [string]$Descriptor.content_sha256) {
    throw "Performance campaign does not bind the immutable context candidate, baseline, target, and Factorio version."
  }
  return [pscustomobject][ordered]@{campaign=$campaign;sha256=(Get-MIRCPSha256File -Path (Resolve-Path -LiteralPath $Path).Path)}
}

function Set-MIRCPCanonicalPerformanceProbeText {
  param([Parameter(Mandatory)][string]$OverlayRoot)
  $relativePath = "fixtures/performance-regression-probe/data-final-fixes.lua"
  $path = Join-Path $OverlayRoot $relativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Performance probe final-fixes source is absent: $path"
  }
  $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
  if ([string]::IsNullOrWhiteSpace($text)) { throw "Performance probe final-fixes source is empty." }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
  [IO.File]::WriteAllBytes($path, $bytes)
  if ($bytes -contains [byte]13) { throw "Canonical performance probe still contains carriage returns." }
  return [pscustomobject][ordered]@{
    path = $relativePath
    materialization = "utf8-no-bom-lf-v1"
    bytes = [int64]$bytes.Length
    line_feeds = @($bytes | Where-Object { $_ -eq 10 }).Count
    sha256 = Get-MIRCPSha256File -Path $path
  }
}

function New-MIRCPPerformanceSourceOverlay {
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)]$Source,
    [Parameter(Mandatory)]$Descriptor,
    [Parameter(Mandatory)]$TargetProfile,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  . (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
  $authorityRelativePath = Get-MIRCPPerformanceCampaignRelativePath -Descriptor $Descriptor -RepoRoot $repo
  $authorityPath = Join-Path $repo $authorityRelativePath
  $authority = Assert-MIRCPPerformanceCampaignAuthority -Path $authorityPath -Descriptor $Descriptor -TargetProfile $TargetProfile -RepoRoot $repo
  $root = Join-Path $repo "build/results/control-plane-v5/source-overlays/$([string]$State.context.context_id)"
  $destination = Join-Path $root "performance"
  if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
    [void](New-Item -ItemType Directory -Force -Path $root)
    $staging = Join-Path $root ("performance-staging-" + [guid]::NewGuid().ToString("N"))
    & git clone --local --no-hardlinks --no-checkout -- ([string]$Source.path) $staging 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Could not clone the immutable qualification source for the performance authority overlay." }
    & git -C $staging checkout --detach ([string]$Source.commit) 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Could not check out the immutable qualification source for the performance authority overlay." }
    Move-Item -LiteralPath $staging -Destination $destination
  }
  $head = ([string](& git -C $destination rev-parse HEAD)).Trim()
  if ($LASTEXITCODE -ne 0 -or $head -ne [string]$Source.commit) { throw "Performance authority overlay source commit differs from the immutable context source." }
  $overlayPath = Join-Path $destination ".mir/performance-campaign.json"
  [IO.File]::Copy($authorityPath, $overlayPath, $true)
  if ((Get-MIRCPSha256File -Path $overlayPath) -ne [string]$authority.sha256) { throw "Performance authority overlay changed the governed campaign bytes." }
  $controllerOverlayRelativePaths = @(
    "scripts/Invoke-MIRCompatAudit.ps1",
    "tools/commands/compatibility/Invoke-MIRCompatAudit.ps1",
    "scripts/MIRCompatAudit/DependencyResolver.ps1",
    "scripts/MIRCompatAudit/DiagnosticsParser.ps1",
    "scripts/MIRCompatAudit/FactorioRunner.ps1",
    "scripts/MIRCompatAudit/ModPortal.ps1",
    "scripts/validation/PackageIdentity.ps1",
    "scripts/validation/PerformanceCampaign.ps1",
    "scripts/validation/ReleaseAttestations.ps1",
    "scripts/validation/SettingsOverrides.ps1",
    "tools/lib/compatibility/DependencyResolver.ps1",
    "tools/lib/compatibility/DiagnosticsParser.ps1",
    "tools/lib/compatibility/FactorioRunner.ps1",
    "tools/lib/compatibility/ModPortal.ps1",
    "tools/lib/validation/PackageIdentity.ps1",
    "tools/lib/validation/PerformanceCampaign.ps1",
    "tools/lib/validation/ReleaseAttestations.ps1",
    "tools/lib/validation/SettingsOverrides.ps1",
    "validation/adapters/portal-exclusions.json",
    "validation/scenarios/local-2.1.json",
    "validation/scenarios/manual.json"
  )
  $controllerOverlayRows = [Collections.Generic.List[object]]::new()
  foreach ($relativePath in $controllerOverlayRelativePaths) {
    $controllerPath = Join-Path $repo $relativePath
    if (-not (Test-Path -LiteralPath $controllerPath -PathType Leaf)) {
      throw "Performance controller overlay dependency is absent: $relativePath"
    }
    $overlayDependencyPath = Join-Path $destination $relativePath
    [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $overlayDependencyPath))
    [IO.File]::Copy($controllerPath, $overlayDependencyPath, $true)
    $sha256 = Get-MIRCPSha256File -Path $controllerPath
    if ((Get-MIRCPSha256File -Path $overlayDependencyPath) -ne $sha256) {
      throw "Performance controller overlay changed dependency bytes: $relativePath"
    }
    $controllerOverlayRows.Add([pscustomobject][ordered]@{
      path = $relativePath
      materialization = "controller-exact-bytes-v1"
      bytes = [int64](Get-Item -LiteralPath $overlayDependencyPath).Length
      sha256 = $sha256
    })
  }
  $probe = Set-MIRCPCanonicalPerformanceProbeText -OverlayRoot $destination
  $status = @(& git -C $destination status --porcelain --untracked-files=all)
  $allowedPaths = @(
    ".mir/performance-campaign.json"
    "fixtures/performance-regression-probe/data-final-fixes.lua"
    $controllerOverlayRelativePaths
  )
  $unexpected = @($status | Where-Object {
    $statusPath = ([string]$_).Substring(3).Replace("\", "/")
    $allowedPaths -notcontains $statusPath
  })
  if ($unexpected.Count -ne 0) { throw "Performance authority overlay contains changes outside its governed package-excluded files." }
  $packageSha256 = Get-MIRPackageSourceFingerprint -RepoRoot $destination
  if ($packageSha256 -ne [string]$Descriptor.source_sha256) { throw "Performance authority overlay changed package-visible source." }
  $harnessSha256 = & {
    param([string]$Root)
    . (Join-Path $Root "tools/lib/validation/PerformanceCampaign.ps1")
    Get-MIRPerformanceHarnessFingerprint -RepoRoot $Root
  } $destination
  $manifest = [pscustomobject][ordered]@{
    schema = 1
    kind = "mir-performance-source-overlay"
    source_commit = [string]$Source.commit
    files = @(
      [pscustomobject][ordered]@{path=".mir/performance-campaign.json";materialization="controller-exact-bytes-v1";bytes=[int64](Get-Item -LiteralPath $overlayPath).Length;sha256=[string]$authority.sha256},
      $probe
      foreach ($controllerOverlayRow in $controllerOverlayRows) { $controllerOverlayRow }
    )
    harness_sha256 = [string]$harnessSha256
    package_source_sha256 = $packageSha256
  }
  return [pscustomobject][ordered]@{
    path = $destination
    authority = $authority
    authority_sha256 = [string]$authority.sha256
    canonical_probe = $probe
    harness_sha256 = [string]$harnessSha256
    manifest = $manifest
    manifest_sha256 = Get-MIRCPSha256Object -Value $manifest
    package_source_sha256 = $packageSha256
  }
}

function New-MIRCPCompactPerformanceArtifactRoot {
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)]$Campaign
  )
  $contextId = [string]$State.context.context_id
  if ($contextId -notmatch '^[0-9A-F]{64}$') {
    throw "Compact performance staging requires an exact context digest."
  }
  $scratchParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $path = Join-Path $scratchParent ("mircp-p-" + $contextId.Substring(0, 24))
  if (Test-Path -LiteralPath $path) {
    throw "Compact performance staging already exists and will not be overwritten: $path"
  }
  $maximumPathLength = 0
  $maximumPath = ""
  foreach ($lane in @($Campaign.lanes | Where-Object { [string]$_.runner -eq "exact-package-load" })) {
    $laneSafe = ([string]$lane.id -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
    $probePath = Join-Path $path ("{0}\measured-25-candidate\mods\mir-fixture-performance-regression-probe_0.1.0\data-final-fixes.lua" -f $laneSafe)
    if ($probePath.Length -gt $maximumPathLength) {
      $maximumPathLength = $probePath.Length
      $maximumPath = $probePath
    }
  }
  foreach ($lane in @($Campaign.lanes | Where-Object { [string]$_.runner -eq "compat-audit" })) {
    $laneSafe = ([string]$lane.id -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
    $compatPath = Join-Path $path ("{0}\measured-25-candidate\compat\runs\u-0123456789ab\mods\mir-validation-settings-overrides\settings-updates.lua" -f $laneSafe)
    if ($compatPath.Length -gt $maximumPathLength) {
      $maximumPathLength = $compatPath.Length
      $maximumPath = $compatPath
    }
  }
  $pathBudget = 240
  if ($maximumPathLength -gt $pathBudget) {
    throw "Compact performance staging exceeds the conservative Factorio path budget ($maximumPathLength > $pathBudget): $maximumPath"
  }
  [void](New-Item -ItemType Directory -Path $path)
  $marker = [pscustomobject][ordered]@{
    schema = 1
    kind = "mir-control-plane-performance-execution-root"
    context_id = $contextId
    strategy = "compact-context-scratch-v1"
    conservative_path_budget = $pathBudget
    maximum_factorio_path_length = $maximumPathLength
  }
  $markerPath = Join-Path $path "control-plane-execution-root.json"
  $marker | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $markerPath -Encoding UTF8
  return [pscustomobject][ordered]@{
    path = $path
    marker_path = $markerPath
    context_id = $contextId
    strategy = [string]$marker.strategy
    conservative_path_budget = $pathBudget
    maximum_factorio_path_length = $maximumPathLength
  }
}

function Move-MIRCPPerformanceArtifacts {
  param(
    [Parameter(Mandatory)]$ExecutionRoot,
    [Parameter(Mandatory)][string]$Destination
  )
  if (-not (Test-Path -LiteralPath ([string]$ExecutionRoot.path) -PathType Container)) {
    throw "Compact performance execution root is absent: $($ExecutionRoot.path)"
  }
  if (Test-Path -LiteralPath $Destination) {
    throw "Performance artifact destination already exists and will not be merged: $Destination"
  }
  $verified = Copy-MIRPerformanceArtifactsVerified -SourceRoot ([string]$ExecutionRoot.path) -DestinationRoot $Destination
  Remove-Item -LiteralPath ([string]$ExecutionRoot.path) -Recurse -Force
  if (Test-Path -LiteralPath ([string]$ExecutionRoot.path)) { throw "Compact performance execution root still exists after verified artifact relocation." }
  $markerPath = Join-Path $Destination "control-plane-execution-root.json"
  if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    throw "Relocated performance artifacts lack their execution-root binding marker."
  }
  $marker = Get-Content -Raw -LiteralPath $markerPath | ConvertFrom-Json
  if ([string]$marker.context_id -ne [string]$ExecutionRoot.context_id -or
      [string]$marker.strategy -ne [string]$ExecutionRoot.strategy) {
    throw "Relocated performance artifacts do not bind the expected context and staging strategy."
  }
  return [pscustomobject][ordered]@{
    path = $Destination
    strategy = [string]$marker.strategy
    context_id = [string]$marker.context_id
    conservative_path_budget = [int]$marker.conservative_path_budget
    maximum_factorio_path_length = [int]$marker.maximum_factorio_path_length
    file_count = [int]$verified.file_count
    bytes = [int64]$verified.bytes
    artifact_tree_sha256 = [string]$verified.artifact_tree_sha256
    artifacts = @($verified.artifacts)
  }
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
  & (Join-Path $source.path "validation/tests/runtime/Test-MIRUpgradeMatrix.ps1") -RepoRoot $source.path `
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

function Get-MIRCPZipPackageObservation {
  param([Parameter(Mandatory)][string]$Path, [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  . (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $archive = [IO.Compression.ZipFile]::OpenRead($resolved)
  try {
    $rows = [Collections.Generic.List[object]]::new()
    $root = ""
    $info = $null
    foreach ($entry in @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | Sort-Object FullName)) {
      $parts = ([string]$entry.FullName).Replace('\', '/').Split('/', 2)
      if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
        throw "Package entry has no versioned root: $($entry.FullName)"
      }
      if ([string]::IsNullOrWhiteSpace($root)) { $root = $parts[0] }
      if ($root -cne $parts[0]) { throw "Package contains more than one versioned root." }
      $stream = $entry.Open()
      $sha = [Security.Cryptography.SHA256]::Create()
      try { $entrySha = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
      finally { $sha.Dispose(); $stream.Dispose() }
      $rows.Add([pscustomobject][ordered]@{path=$parts[1];sha256=$entrySha;bytes=[int64]$entry.Length})
      if ($parts[1] -ceq "info.json") {
        $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8, $true)
        try { $info = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
      }
    }
  } finally {
    $archive.Dispose()
  }
  if ($null -eq $info) { throw "Package has no root info.json." }
  return [pscustomobject][ordered]@{
    path = $resolved
    name = [string]$info.name
    version = [string]$info.version
    factorio_version = [string]$info.factorio_version
    archive_sha256 = Get-MIRCPSha256File -Path $resolved
    content_sha256 = Get-MIRZipContentFingerprint -Path $resolved
    bytes = [int64](Get-Item -LiteralPath $resolved).Length
    entries = $rows.Count
    files = @($rows)
  }
}

function Test-MIRCPExactPathSet {
  param([object[]]$Expected, [object[]]$Actual)
  $expectedRows = @($Expected | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  $actualRows = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  return ($expectedRows -join "`n") -ceq ($actualRows -join "`n")
}

function Get-MIRCPNativePatchDeltaPolicy {
  param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$FromVersion,
    [Parameter(Mandatory)][string]$ToVersion,
    [Parameter(Mandatory)][string]$CandidateId,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $authority = Read-MIRCPJson -Path ".mir/control-plane/approved-delta-policies.json" -RepoRoot $repo
  if ([int]$authority.schema -ne 1 -or [string]$authority.authority -ne "mir-control-plane-v5-approved-delta-policies") {
    throw "Approved-delta policy authority is invalid."
  }
  $matches = @($authority.policies | Where-Object {
    [string]$_.target -eq $Target -and [string]$_.from_version -eq $FromVersion -and
    [string]$_.to_version -eq $ToVersion -and [string]$_.candidate_id -eq $CandidateId
  })
  if ($matches.Count -gt 1) {
    throw "More than one native approved-delta policy matches $FromVersion -> $ToVersion $CandidateId."
  }
  return @($matches)
}
function Invoke-MIRCPNativePatchDeltaMeasurement {
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)]$PlanRow,
    [Parameter(Mandatory)]$Source,
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$PriorRelease,
    [Parameter(Mandatory)]$Factorio,
    [Parameter(Mandatory)][string]$TrustClass,
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  . (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $State.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $policyAuthorityPath = Join-Path $repo ".mir/control-plane/approved-delta-policies.json"
  $baseline = Get-MIRCPZipPackageObservation -Path $PriorRelease
  $current = Get-MIRCPZipPackageObservation -Path $Candidate
  $policies = @(Get-MIRCPNativePatchDeltaPolicy -Target ([string]$State.plan.target) `
    -FromVersion ([string]$baseline.version) -ToVersion ([string]$current.version) `
    -CandidateId ([string]$descriptor.candidate_id) -RepoRoot $repo)
  if ($policies.Count -ne 1) { throw "Expected exactly one native approved-delta policy for $($baseline.version) -> $($current.version) $($descriptor.candidate_id)." }
  $policy = $policies[0]
  $baselineByPath = @{}
  foreach ($file in @($baseline.files)) { $baselineByPath[[string]$file.path] = [string]$file.sha256 }
  $currentByPath = @{}
  foreach ($file in @($current.files)) { $currentByPath[[string]$file.path] = [string]$file.sha256 }
  $added = @($currentByPath.Keys | Where-Object { -not $baselineByPath.ContainsKey($_) } | Sort-Object)
  $removed = @($baselineByPath.Keys | Where-Object { -not $currentByPath.ContainsKey($_) } | Sort-Object)
  $changed = @($currentByPath.Keys | Where-Object { $baselineByPath.ContainsKey($_) -and $baselineByPath[$_] -cne $currentByPath[$_] } | Sort-Object)
  $baselineAuthority = $policy.baseline
  $candidateAuthority = $policy.candidate
  $predicates = @(
    [pscustomobject][ordered]@{id="baseline-version";passed=([string]$baseline.version -eq [string]$policy.from_version)},
    [pscustomobject][ordered]@{id="baseline-archive";passed=([string]$baseline.archive_sha256 -eq [string]$baselineAuthority.archive_sha256 -and [string]$baseline.content_sha256 -eq [string]$baselineAuthority.content_sha256 -and [int64]$baseline.bytes -eq [int64]$baselineAuthority.bytes -and [int]$baseline.entries -eq [int]$baselineAuthority.entries)},
    [pscustomobject][ordered]@{id="candidate-version";passed=([string]$current.version -eq [string]$policy.to_version)},
    [pscustomobject][ordered]@{id="candidate-archive";passed=([string]$current.archive_sha256 -eq [string]$candidateAuthority.archive_sha256 -and [string]$current.content_sha256 -eq [string]$candidateAuthority.content_sha256 -and [int64]$current.bytes -eq [int64]$candidateAuthority.bytes -and [int]$current.entries -eq [int]$candidateAuthority.entries)},
    [pscustomobject][ordered]@{id="context-candidate";passed=([string]$descriptor.source_commit -eq [string]$candidateAuthority.source_commit -and [string]$descriptor.archive_sha256 -eq [string]$candidateAuthority.archive_sha256 -and [string]$descriptor.content_sha256 -eq [string]$candidateAuthority.content_sha256)},
    [pscustomobject][ordered]@{id="qualification-source";passed=([string]$Source.commit -eq [string]$candidateAuthority.source_commit)},
    [pscustomobject][ordered]@{id="added-paths";passed=(Test-MIRCPExactPathSet -Expected @($policy.allowed_added_paths) -Actual $added)},
    [pscustomobject][ordered]@{id="removed-paths";passed=(Test-MIRCPExactPathSet -Expected @($policy.allowed_removed_paths) -Actual $removed)},
    [pscustomobject][ordered]@{id="changed-paths";passed=(Test-MIRCPExactPathSet -Expected @($policy.allowed_changed_paths) -Actual $changed)}
  )
  $failedPredicates = @($predicates | Where-Object { -not [bool]$_.passed })
  $unexpected = @(
    @($added | Where-Object { @($policy.allowed_added_paths) -notcontains $_ })
    @($removed | Where-Object { @($policy.allowed_removed_paths) -notcontains $_ })
    @($changed | Where-Object { @($policy.allowed_changed_paths) -notcontains $_ })
  )
  $missing = @(
    @($policy.allowed_added_paths | Where-Object { $added -notcontains [string]$_ })
    @($policy.allowed_removed_paths | Where-Object { $removed -notcontains [string]$_ })
    @($policy.allowed_changed_paths | Where-Object { $changed -notcontains [string]$_ })
  )
  $status = if ($failedPredicates.Count -eq 0) { "approved" } else { "rejected" }
  $output = [pscustomobject][ordered]@{
    schema = 1
    kind = "mir-control-plane-v5-approved-patch-delta"
    policy = [pscustomobject][ordered]@{id=[string]$policy.id;authority_digest_policy="utf8-lf";authority_sha256=(Get-MIRCPPortableTextSha256 -Path $policyAuthorityPath);reason=[string]$policy.reason;migration_impact=[string]$policy.migration_impact;allowed_added_paths=@($policy.allowed_added_paths);allowed_removed_paths=@($policy.allowed_removed_paths);allowed_changed_paths=@($policy.allowed_changed_paths)}
    observation = [pscustomobject][ordered]@{
      baseline = [pscustomobject][ordered]@{version=[string]$baseline.version;source_commit=[string]$baselineAuthority.source_commit;archive_sha256=[string]$baseline.archive_sha256;content_sha256=[string]$baseline.content_sha256;bytes=[int64]$baseline.bytes;entries=[int]$baseline.entries}
      current = [pscustomobject][ordered]@{version=[string]$current.version;candidate_id=[string]$descriptor.candidate_id;source_commit=[string]$candidateAuthority.source_commit;qualification_source_commit=[string]$Source.commit;archive_sha256=[string]$current.archive_sha256;content_sha256=[string]$current.content_sha256;bytes=[int64]$current.bytes;entries=[int]$current.entries}
      delta = [pscustomobject][ordered]@{added=$added;removed=$removed;changed=$changed}
    }
    evaluation = [pscustomobject][ordered]@{status=$status;difference_count=($added.Count + $removed.Count + $changed.Count);unapproved_count=($unexpected.Count + $missing.Count);predicates=$predicates}
  }
  $outputPath = Join-Path $repo "build/results/control-plane-v5/approved-delta/$([string]$State.context.context_id)/evaluation.json"
  Write-MIRCPJson -Path $outputPath -Value $output -RepoRoot $repo
  $taskStatus = if ($status -eq "approved" -and [int]$output.evaluation.unapproved_count -eq 0) { "passed" } else { "failed" }
  $facts = [pscustomobject][ordered]@{
    status = $taskStatus
    measurement_mode = "native-patch-delta-v1"
    policy_id = [string]$policy.id
    policy_authority_digest_policy = "utf8-lf"
    policy_authority_sha256 = Get-MIRCPPortableTextSha256 -Path $policyAuthorityPath
    factorio_installation_sha256 = [string]$Factorio.installation_sha256
    factorio_binary_sha256 = [string]$Factorio.binary.sha256
    prior_archive_sha256 = [string]$baseline.archive_sha256
    difference_count = [int]$output.evaluation.difference_count
    unapproved_count = [int]$output.evaluation.unapproved_count
    artifact_status = $status
  }
  return Write-MIRCPSpecializedTaskEvidence -State $State -PlanRow $PlanRow -ObservationKind environment-capture -Status $taskStatus `
    -EnvironmentMaterial ([pscustomobject][ordered]@{task=[string]$PlanRow.effective_input_sha256;factorio=$Factorio;prior_archive_sha256=$facts.prior_archive_sha256;source_commit=[string]$Source.commit;policy_authority_sha256=$facts.policy_authority_sha256}) `
    -Facts $facts -ArtifactPath $outputPath -ArtifactKind "approved-patch-delta-evaluation" -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
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
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $repo
  $source = Assert-MIRCPExecutionSource -State $state -SourceRepoRoot $SourceRepoRoot
  $candidate = Get-MIRCPCanonicalCandidateArchive -State $state -RepoRoot $repo
  $row = @($state.plan.tasks | Where-Object id -eq "approved-delta.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain approved-delta.measurement exactly once." }
  $factorio = Assert-MIRCPFactorioContextLock -State $state -FactorioBin $FactorioBin
  $prior = (Resolve-Path -LiteralPath $PriorRelease).Path
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $priorObservation = Get-MIRCPZipPackageObservation -Path $prior
  $nativePolicies = @(Get-MIRCPNativePatchDeltaPolicy -Target ([string]$state.plan.target) `
    -FromVersion ([string]$priorObservation.version) -ToVersion ([string]$descriptor.release) `
    -CandidateId ([string]$descriptor.candidate_id) -RepoRoot $repo)
  if ($nativePolicies.Count -eq 1) {
    return Invoke-MIRCPNativePatchDeltaMeasurement -State $state -PlanRow $row[0] -Source $source -Candidate $candidate `
      -PriorRelease $prior -Factorio $factorio -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
  }
  $outputPath = Join-Path $repo "build/results/control-plane-v5/approved-delta.json"
  $rawRoot = Join-Path $repo "build/results/control-plane-v5/approved-delta-raw"
  & (Join-Path $source.path "scripts/Export-MIRApprovedDelta.ps1") -BaselinePackage $prior `
    -CurrentPackage $candidate -FactorioBin $factorio.path `
    -OutputPath $outputPath -EvidenceRoot $rawRoot -ExpectedBaselineSha256 (Get-MIRCPSha256File -Path $prior) `
    -ExpectedSourceCommit ([string]$source.commit)
  $exportExitCode = $LASTEXITCODE
  if ($exportExitCode -eq 0) {
    & (Join-Path $source.path "validation/tests/release/Test-MIRApprovedDelta.ps1") -Path $outputPath `
      -Candidate $candidate -ExpectedSourceCommit ([string]$source.commit)
  }
  $testExitCode = $LASTEXITCODE
  $artifact = if (Test-Path -LiteralPath $outputPath -PathType Leaf) { Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json } else { $null }
  $status = if ($exportExitCode -eq 0 -and $testExitCode -eq 0 -and $null -ne $artifact -and [string]$artifact.summary.status -eq "approved" -and [int]$artifact.summary.unapproved_count -eq 0) { "passed" } else { "failed" }
  $facts = [pscustomobject][ordered]@{
    status = $status
    factorio_installation_sha256 = [string]$factorio.installation_sha256
    factorio_binary_sha256 = [string]$factorio.binary.sha256
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
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $repo
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
    if ($matches.Count -gt 1) { throw "Aggregate gate found ambiguous evidence for TaskNode $($row.id)." }
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
    $memberPayload = @($memberResults | ForEach-Object { [pscustomobject][ordered]@{task_id=[string]$_.task_id;object_digest=[string]$_.object_digest} })
    $aggregateMatches = @($objects | Where-Object {
      [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq [string]$row.id -and
      [string]$_.context_digest -eq [string]$state.context.context_id -and
      [string]$_.identity_key -eq [string]$row.effective_input_sha256 -and
      [string]$_.status -eq "passed" -and [string]$_.trust_class -eq $TrustClass -and -not [bool]$_.revoked
    })
    if ($aggregateMatches.Count -gt 1) { throw "Aggregate gate found ambiguous evidence for aggregate TaskNode $($row.id)." }
    if ($aggregateMatches.Count -eq 1) {
      $existingAggregate = (Read-MIRCPEvidenceObject -Digest ([string]$aggregateMatches[0].digest) -RepoRoot $repo -Root $EvidenceRoot).object
      if (-not [bool]$existingAggregate.payload.aggregate -or
          (Get-MIRCPSha256Object -Value @($existingAggregate.payload.members)) -ne (Get-MIRCPSha256Object -Value $memberPayload)) {
        throw "Existing aggregate TaskNode $($row.id) does not bind the exact selected member closure."
      }
      $aggregateMarker = [pscustomobject][ordered]@{
        schema = 1
        task_id = [string]$row.id
        status = "passed"
        context_digest = [string]$state.context.context_id
        identity_key = [string]$row.effective_input_sha256
        object_digest = [string]$aggregateMatches[0].digest
      }
    } else {
      $aggregateMarker = Write-MIRCPTaskResultEvidence -State $state -PlanRow $row -Status passed `
        -Payload ([pscustomobject][ordered]@{aggregate=$true;members=$memberPayload}) `
        -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
    }
    $taskResults.Add($aggregateMarker)
  }
  $producer = New-MIRCPExecutorProducer -TrustClass $TrustClass -RepoRoot $repo
  $manifest = New-MIRCPExecutionManifest -ContextDigest ([string]$state.context.context_id) -PlanId ([string]$state.plan_envelope.plan_id) -Producer $producer -TaskResults @($taskResults) -Status passed
  $manifestObject = New-MIRCPEvidenceObject -Kind execution-manifest -ContextDigest ([string]$state.context.context_id) -IdentityKey (Get-MIRCPSha256Object -Value $manifest) `
    -Subject ([pscustomobject][ordered]@{plan_id=[string]$state.plan_envelope.plan_id;target=[string]$state.plan.target}) -Producer $producer -Payload $manifest -Links @($taskResults.object_digest)
  $stored = Write-MIRCPEvidenceObject -Object $manifestObject -RepoRoot $repo -Root $EvidenceRoot
  return [pscustomobject][ordered]@{status="passed";context_digest=[string]$state.context.context_id;plan_id=[string]$state.plan_envelope.plan_id;aggregate_task=if([string]::IsNullOrWhiteSpace($AggregateTaskId)){"all"}else{$AggregateTaskId};task_results=$taskResults.Count;manifest_object=[string]$stored.digest}
}
