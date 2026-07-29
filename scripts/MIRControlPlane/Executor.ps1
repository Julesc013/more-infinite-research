function Get-MIRCPContextExecutionState {
  param([Parameter(Mandatory)][string]$ContextPath, [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $context = Assert-MIRCPVerificationContext -Path $ContextPath
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $context.path "context-manifest.json") | ConvertFrom-Json
  if ([int]$manifest.context_abi -ne 2) { throw "Context execution requires verification context ABI 2." }
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
  $root = Join-Path $repo "out/control-plane-v5/context-candidates/$([string]$State.context.context_id)"
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

function Get-MIRCPFactorioIdentity {
  param([Parameter(Mandatory)][string]$FactorioBin)
  $binary = (Resolve-Path -LiteralPath $FactorioBin).Path
  $binaryItem = Get-Item -LiteralPath $binary
  if ($null -eq $script:MIRCPFactorioIdentityCache) { $script:MIRCPFactorioIdentityCache = @{} }
  $cacheKey = "$binary|$($binaryItem.Length)|$($binaryItem.LastWriteTimeUtc.Ticks)"
  if ($script:MIRCPFactorioIdentityCache.ContainsKey($cacheKey)) { return $script:MIRCPFactorioIdentityCache[$cacheKey] }
  $installRoot = $binaryItem.Directory.Parent.Parent.FullName
  $officialRoots = @("data/core", "data/base", "data/quality", "data/elevated-rails", "data/space-age")
  $officialFiles = @()
  foreach ($relativeRoot in $officialRoots) {
    $path = Join-Path $installRoot $relativeRoot
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $officialFiles += Get-Item -LiteralPath $path
    } elseif (Test-Path -LiteralPath $path -PathType Container) {
      $officialFiles += Get-ChildItem -LiteralPath $path -Recurse -File
    }
  }
  $officialRows = @(
    foreach ($file in @($officialFiles | Sort-Object FullName -Unique)) {
      $relative = [IO.Path]::GetRelativePath($installRoot, $file.FullName).Replace("\", "/")
      "$relative`t$($file.Length)`t$(Get-MIRCPSha256File -Path $file.FullName)"
    }
  )
  $officialData = [pscustomobject][ordered]@{
    kind = "external-tree"
    state = "present"
    root = $installRoot
    file_count = $officialRows.Count
    sha256 = Get-MIRCPSha256Text -Value $(if ($officialRows.Count -gt 0) { $officialRows -join "`n" } else { "EMPTY:factorio-official-data" })
  }
  $binarySha256 = Get-MIRCPSha256File -Path $binary
  $binaryFingerprint = [pscustomobject][ordered]@{
    kind = "external-file"
    state = "present"
    name = $binaryItem.Name
    size_bytes = [int64]$binaryItem.Length
    sha256 = $binarySha256
  }
  $installationMaterial = [ordered]@{binary=$binaryFingerprint;official_data=$officialData}
  # Environment locks imported from v4 retain the v4 ordered compact-JSON identity.
  $installationSha256 = Get-MIRCPSha256Text -Value ($installationMaterial | ConvertTo-Json -Depth 40 -Compress)
  $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($binary).FileVersion
  $identity = [pscustomobject][ordered]@{
    path = $binary
    root = $installRoot
    sha256 = $installationSha256
    installation_sha256 = $installationSha256
    bytes = [int64]$binaryItem.Length
    version = [string]$version
    binary = [pscustomobject][ordered]@{bytes=[int64]$binaryItem.Length;sha256=$binarySha256}
    official_data = $officialData
  }
  $script:MIRCPFactorioIdentityCache[$cacheKey] = $identity
  return $identity
}

function Test-MIRCPFactorioIdentityMatchesLock {
  param(
    [Parameter(Mandatory)]$Identity,
    [Parameter(Mandatory)]$Lock
  )
  if ($null -ne $Lock.PSObject.Properties["installation_sha256"] -and
      [string]$Lock.installation_sha256 -ne [string]$Identity.installation_sha256) { return $false }
  if ([string]$Lock.binary.sha256 -ne [string]$Identity.binary.sha256) { return $false }
  if ($null -ne $Lock.binary.PSObject.Properties["bytes"] -and [int64]$Lock.binary.bytes -gt 0 -and
      [int64]$Lock.binary.bytes -ne [int64]$Identity.binary.bytes) { return $false }
  if ($null -ne $Lock.PSObject.Properties["version"] -and -not [string]::IsNullOrWhiteSpace([string]$Lock.version) -and
      [string]$Lock.version -ne [string]$Identity.version) { return $false }
  if ($null -ne $Lock.PSObject.Properties["official_data"] -and $null -ne $Lock.official_data) {
    if ([int]$Lock.official_data.file_count -ne [int]$Identity.official_data.file_count -or
        [string]$Lock.official_data.sha256 -ne [string]$Identity.official_data.sha256) { return $false }
  }
  return $true
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
  $summaryRoot = Join-Path $repo "out/control-plane-v5/environment-results"
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
  [void](Assert-MIRCPFactorioContextLock -State $state -FactorioBin $FactorioBin)
  $row = @($state.plan.tasks | Where-Object id -eq "performance.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain performance.measurement exactly once." }
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $profile = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "target-profile.json") | ConvertFrom-Json
  $outputPath = Join-Path $repo "out/control-plane-v5/performance-evidence.json"
  $arguments = @{
    RepoRoot = $source.path
    Candidate = $candidate
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
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $repo
  $source = Assert-MIRCPExecutionSource -State $state -SourceRepoRoot $SourceRepoRoot
  $candidate = Get-MIRCPCanonicalCandidateArchive -State $state -RepoRoot $repo
  $row = @($state.plan.tasks | Where-Object id -eq "upgrade.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain upgrade.measurement exactly once." }
  $profile = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "target-profile.json") | ConvertFrom-Json
  $factorio = Assert-MIRCPFactorioContextLock -State $state -FactorioBin $FactorioBin
  $prior = (Resolve-Path -LiteralPath $PriorRelease).Path
  $outputPath = Join-Path $repo "out/control-plane-v5/upgrade-evidence.json"
  & (Join-Path $source.path "scripts/Test-MIRUpgradeMatrix.ps1") -RepoRoot $source.path `
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
  $outputRoot = Join-Path $repo "out/control-plane-v5/ecosystem"
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
  param([Parameter(Mandatory)][string]$Path)
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
  . (Join-Path $repo "scripts/validation/PackageIdentity.ps1")
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $State.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $policyAuthorityPath = Join-Path $repo ".mir/control-plane/approved-delta-policies.json"
  $policyAuthority = Get-Content -Raw -LiteralPath $policyAuthorityPath | ConvertFrom-Json
  if ([int]$policyAuthority.schema -ne 1 -or [string]$policyAuthority.authority -ne "mir-control-plane-v5-approved-delta-policies") {
    throw "Approved-delta policy authority is invalid."
  }
  $baseline = Get-MIRCPZipPackageObservation -Path $PriorRelease
  $current = Get-MIRCPZipPackageObservation -Path $Candidate
  $policies = @($policyAuthority.policies | Where-Object {
    [string]$_.target -eq [string]$State.plan.target -and [string]$_.from_version -eq [string]$baseline.version -and
    [string]$_.to_version -eq [string]$current.version -and [string]$_.candidate_id -eq [string]$descriptor.candidate_id
  })
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
    policy = [pscustomobject][ordered]@{id=[string]$policy.id;authority_sha256=(Get-MIRCPSha256File -Path $policyAuthorityPath);reason=[string]$policy.reason;migration_impact=[string]$policy.migration_impact;allowed_added_paths=@($policy.allowed_added_paths);allowed_removed_paths=@($policy.allowed_removed_paths);allowed_changed_paths=@($policy.allowed_changed_paths)}
    observation = [pscustomobject][ordered]@{
      baseline = [pscustomobject][ordered]@{version=[string]$baseline.version;source_commit=[string]$baselineAuthority.source_commit;archive_sha256=[string]$baseline.archive_sha256;content_sha256=[string]$baseline.content_sha256;bytes=[int64]$baseline.bytes;entries=[int]$baseline.entries}
      current = [pscustomobject][ordered]@{version=[string]$current.version;candidate_id=[string]$descriptor.candidate_id;source_commit=[string]$candidateAuthority.source_commit;qualification_source_commit=[string]$Source.commit;archive_sha256=[string]$current.archive_sha256;content_sha256=[string]$current.content_sha256;bytes=[int64]$current.bytes;entries=[int]$current.entries}
      delta = [pscustomobject][ordered]@{added=$added;removed=$removed;changed=$changed}
    }
    evaluation = [pscustomobject][ordered]@{status=$status;difference_count=($added.Count + $removed.Count + $changed.Count);unapproved_count=($unexpected.Count + $missing.Count);predicates=$predicates}
  }
  $outputPath = Join-Path $repo "out/control-plane-v5/approved-delta/$([string]$State.context.context_id)/evaluation.json"
  Write-MIRCPJson -Path $outputPath -Value $output -RepoRoot $repo
  $taskStatus = if ($status -eq "approved" -and [int]$output.evaluation.unapproved_count -eq 0) { "passed" } else { "failed" }
  $facts = [pscustomobject][ordered]@{
    status = $taskStatus
    measurement_mode = "native-patch-delta-v1"
    policy_id = [string]$policy.id
    policy_authority_sha256 = Get-MIRCPSha256File -Path $policyAuthorityPath
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
  if ([string]$priorObservation.version -eq "3.2.1" -and [string]$descriptor.release -eq "3.2.2") {
    return Invoke-MIRCPNativePatchDeltaMeasurement -State $state -PlanRow $row[0] -Source $source -Candidate $candidate `
      -PriorRelease $prior -Factorio $factorio -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
  }
  $outputPath = Join-Path $repo "out/control-plane-v5/approved-delta.json"
  $rawRoot = Join-Path $repo "out/control-plane-v5/approved-delta-raw"
  & (Join-Path $source.path "scripts/Export-MIRApprovedDelta.ps1") -BaselinePackage $prior `
    -CurrentPackage $candidate -FactorioBin $factorio.path `
    -OutputPath $outputPath -EvidenceRoot $rawRoot -ExpectedBaselineSha256 (Get-MIRCPSha256File -Path $prior) `
    -ExpectedSourceCommit ([string]$source.commit)
  $exportExitCode = $LASTEXITCODE
  if ($exportExitCode -eq 0) {
    & (Join-Path $source.path "scripts/Test-MIRApprovedDelta.ps1") -Path $outputPath `
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
