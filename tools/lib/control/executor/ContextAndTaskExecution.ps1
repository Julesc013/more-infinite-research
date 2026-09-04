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
