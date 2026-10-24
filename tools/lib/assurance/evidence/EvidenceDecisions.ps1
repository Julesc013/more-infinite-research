function ConvertTo-MIRAssuranceOrderedMap {
  param([Parameter(Mandatory)]$Object)
  $map = [ordered]@{}
  if ($Object -is [System.Collections.IDictionary]) {
    foreach ($key in $Object.Keys) { $map[[string]$key] = $Object[$key] }
  } else {
    foreach ($property in $Object.PSObject.Properties) { $map[$property.Name] = $property.Value }
  }
  return $map
}

function Write-MIRAssuranceOrphanedRunningLeaseCustody {
  param(
    [Parameter(Mandatory)]$Paths,
    [Parameter(Mandatory)]$Running,
    [Parameter(Mandatory)]$CurrentProducer,
    [Parameter(Mandatory)][string]$Reason
  )
  # A cache restore supplies completed filesystem bytes. It can preserve a
  # running lease as custody, but cannot reconnect that producer to this
  # worker's private restored directory.
  if (-not (Test-Path -LiteralPath $Paths.running -PathType Leaf)) { return $null }
  $markerSha256 = Get-MIRAssuranceSha256 -Path $Paths.running
  $currentProducerMap = ConvertTo-MIRAssuranceOrderedMap -Object $CurrentProducer
  $currentProducerSha256 = Get-MIRAssuranceJsonHash -Value $currentProducerMap
  $directory = Join-Path $Paths.root 'lease-custody'
  $path = Join-Path $directory ("{0}-{1}.json" -f $markerSha256.ToLowerInvariant(), $currentProducerSha256.ToLowerInvariant())
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    $record = [ordered]@{
      schema=1
      kind='mir-assurance-orphaned-running-lease-v1'
      reason=$Reason
      observed_at=[DateTimeOffset]::UtcNow.ToString('o')
      marker_sha256=$markerSha256
      current_producer=$currentProducerMap
      marker=$Running
    }
    $record['record_sha256'] = Get-MIRAssuranceJsonHash -Value $record
    Write-MIRAssuranceAtomicJson -Value $record -Path $path
  }
  Remove-Item -LiteralPath $Paths.running -Force
  return $path
}

function Get-MIRAssuranceReusableEvidence {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context,
    $Test = $null,
    $Lock = $null
  )
  $identity = [ordered]@{
    test_id=[string]$Fingerprint.test_id
    input_key=[string]$Fingerprint.input_key
    target=[string]$Fingerprint.target
    fingerprint_sha256=[string]$Fingerprint.fingerprint_sha256
    definition_sha256=[string]$Fingerprint.definition_sha256
  }
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  $ownsLock = $null -eq $Lock
  if ($ownsLock) {
    $Lock = Enter-MIRAssuranceAttemptStateLock -Identity $identity
  } else {
    Assert-MIRAssuranceAttemptStateLock -Identity $identity -Lock $Lock
  }
  try {
    # Every reusable lookup is also a lease-reconciliation point. In
    # particular, aggregation traverses every planned identity before it saves
    # the ledger, so a completed cache snapshot cannot carry an orphaned CI
    # worker marker into the next run.
    $null = Get-MIRAssuranceRunningEvidence -Fingerprint $Fingerprint -Context $Context
    # Never trust passed.json alone.  A durable immutable attempt may have been
    # published before a crashed producer reached its pointer transition.
    $snapshot = Get-MIRAssuranceAttemptStateSnapshot -Identity $identity -Context $Context -Lock $Lock
    if (@($snapshot.unresolved).Count -gt 0) {
      # Complete the deferred pointer transition under the same observation
      # lock.  This is recoverable crash repair, not a new trust decision.
      $null = Set-MIRAssuranceQuarantinedPointer -Identity $identity -StateSnapshot $snapshot -Lock $Lock
      return $null
    }
    if (-not (Test-Path -LiteralPath $paths.passed -PathType Leaf)) { return $null }
    if (Test-Path -LiteralPath $paths.blocked -PathType Leaf) { return $null }
    $capsule = Read-MIRAssuranceEvidencePointer -Path $paths.passed
    if ($null -eq $capsule) { return $null }
    $validation = Test-MIRAssuranceCapsule -Capsule $capsule -Fingerprint $Fingerprint -Context $Context -Test $Test
    if (-not [bool]$validation.valid) { return $null }
    $result = ConvertTo-MIRAssuranceOrderedMap -Object $capsule
    $result.disposition = "REUSE"
    $result.decision_reason = [string]$validation.reason
    $result.reused_at = (Get-Date).ToUniversalTime().ToString("o")
    $result.source_duration_seconds = [double]$capsule.duration_seconds
    $result.duration_seconds = 0
    $result.evidence_path = Get-MIRAssuranceRepoRelativePath -Path $paths.passed
    return $result
  } finally {
    if ($ownsLock) { Exit-MIRAssuranceAttemptStateLock -Lock $Lock }
  }
}

function Get-MIRAssuranceCampaignCheckpoint {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  if (-not [bool]$Test.force_fresh) { return $null }
  $checkpoint = Get-MIRAssuranceReusableEvidence -Fingerprint $Test.fingerprint -Context $Context -Test $Test
  if ($null -eq $checkpoint -or -not (Test-MIRAssuranceFreshCampaignEvidence -Capsule $checkpoint -Test $Test -Plan $Plan)) {
    return $null
  }
  $checkpoint.disposition = "CHECKPOINT"
  $checkpoint.decision_reason = "exact-plan-owned-fresh-checkpoint"
  $checkpoint.checkpointed_at = (Get-Date).ToUniversalTime().ToString("o")
  return $checkpoint
}

function Get-MIRAssuranceRunningEvidence {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    $Context = $null
  )
  # A caller that explicitly requests fresh execution must not be held by a
  # restored running marker.  The marker remains available to ordinary
  # matching workers; this request will overwrite it only when it begins its
  # own exact attempt.
  if ($null -ne $Context -and (
      -not [bool]$Context.reuse_enabled -or
      @($Context.rerun_tests | Where-Object { [string]$_ -eq [string]$Fingerprint.test_id }).Count -gt 0)) {
    return $null
  }
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if (-not (Test-Path -LiteralPath $paths.running -PathType Leaf)) { return $null }
  try { $running = Get-Content -Raw -LiteralPath $paths.running | ConvertFrom-Json }
  catch {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  if ([int]$running.schema -ne 2 -or
      [string]$running.test_id -ne [string]$Fingerprint.test_id -or
      [string]$running.input_key -ne [string]$Fingerprint.input_key -or
      [string]$running.fingerprint_sha256 -ne [string]$Fingerprint.fingerprint_sha256) {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  if ($null -ne $Context -and -not (Test-MIRAssuranceTrustedProducer -Producer $running.producer -Context $Context)) {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  try { $expires = ConvertTo-MIRAssuranceDateTimeOffset -Value $running.expires_at }
  catch {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  if ($expires -le [DateTimeOffset]::UtcNow) {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }

  $hostIdentity = [string]$running.host_identity
  if ([string]::IsNullOrWhiteSpace($hostIdentity)) {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  switch ([string]$running.lease_scope) {
    "process" {
      if ($hostIdentity -ne (Get-MIRAssuranceHostIdentity) -or [int]$running.process_id -le 0) {
        Remove-Item -LiteralPath $paths.running -Force
        return $null
      }
      try { $expectedProcessStart = ConvertTo-MIRAssuranceDateTimeOffset -Value $running.process_started_at }
      catch {
        Remove-Item -LiteralPath $paths.running -Force
        return $null
      }
      $process = Get-Process -Id ([int]$running.process_id) -ErrorAction SilentlyContinue
      if ($null -eq $process) {
        Remove-Item -LiteralPath $paths.running -Force
        return $null
      }
      $actualProcessStart = [DateTimeOffset]$process.StartTime.ToUniversalTime()
      if ($actualProcessStart.UtcTicks -ne $expectedProcessStart.UtcTicks) {
        Remove-Item -LiteralPath $paths.running -Force
        return $null
      }
    }
    "ci-job" {
      $runId = [string]$running.workflow_run_id
      $runAttempt = [string]$running.workflow_run_attempt
      $job = [string]$running.workflow_job
      if ([string]::IsNullOrWhiteSpace($runId) -or
          [string]::IsNullOrWhiteSpace($runAttempt) -or
          [string]::IsNullOrWhiteSpace($job) -or
          $runId -ne [string]$running.producer.run_id -or
          $runAttempt -ne [string]$running.producer.run_attempt -or
          $job -ne [string]$running.producer.job) {
        Remove-Item -LiteralPath $paths.running -Force
        return $null
      }
      $currentProducer = Get-MIRAssuranceProducer
      $sameJob = $runId -eq [string]$currentProducer.run_id -and
        $runAttempt -eq [string]$currentProducer.run_attempt -and
        $job -eq [string]$currentProducer.job
      if (-not $sameJob) {
        $null = Write-MIRAssuranceOrphanedRunningLeaseCustody `
          -Paths $paths `
          -Running $running `
          -CurrentProducer $currentProducer `
          -Reason 'ci-job-lease-not-live-in-current-worker'
        return $null
      }
      if ($hostIdentity -ne (Get-MIRAssuranceHostIdentity)) {
        $null = Write-MIRAssuranceOrphanedRunningLeaseCustody `
          -Paths $paths `
          -Running $running `
          -CurrentProducer $currentProducer `
          -Reason 'ci-job-host-identity-mismatch'
        return $null
      }
      $liveProcess = $false
      try {
        if ([int]$running.process_id -gt 0) {
          $expectedProcessStart = ConvertTo-MIRAssuranceDateTimeOffset -Value $running.process_started_at
          $process = Get-Process -Id ([int]$running.process_id) -ErrorAction SilentlyContinue
          if ($null -ne $process) {
            $actualProcessStart = [DateTimeOffset]$process.StartTime.ToUniversalTime()
            $liveProcess = $actualProcessStart.UtcTicks -eq $expectedProcessStart.UtcTicks
          }
        }
      } catch { $liveProcess = $false }
      if (-not $liveProcess) {
        $null = Write-MIRAssuranceOrphanedRunningLeaseCustody `
          -Paths $paths `
          -Running $running `
          -CurrentProducer $currentProducer `
          -Reason 'ci-job-process-not-live-in-current-worker'
        return $null
      }
    }
    default {
      Remove-Item -LiteralPath $paths.running -Force
      return $null
    }
  }
  return $running
}

function Get-MIRAssuranceEvidenceDecision {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$TestId,
    $Test = $null
  )
  $fingerprintInputs = if ($Fingerprint -is [System.Collections.IDictionary] -and $Fingerprint.Contains('inputs')) {
    $Fingerprint['inputs']
  } elseif ($null -ne $Fingerprint.PSObject.Properties['inputs']) {
    $Fingerprint.PSObject.Properties['inputs'].Value
  } else {
    $null
  }
  $inputMap = if ($null -eq $fingerprintInputs) {
    [ordered]@{}
  } else {
    ConvertTo-MIRAssuranceOrderedMap -Object $fingerprintInputs
  }
  $missingInputs = @(
    foreach ($inputName in @($inputMap.Keys | Sort-Object)) {
      $inputValue = $inputMap[$inputName]
      $state = if ($inputValue -is [System.Collections.IDictionary] -and $inputValue.Contains('state')) {
        [string]$inputValue['state']
      } elseif ($null -ne $inputValue -and $null -ne $inputValue.PSObject.Properties['state']) {
        [string]$inputValue.PSObject.Properties['state'].Value
      } else {
        ''
      }
      if ($state -eq "missing") {
        [string]$inputName
      }
    }
  )
  if ($missingInputs.Count -gt 0) {
    return [ordered]@{disposition="INVALID"; reason="required-input-missing:$($missingInputs -join ',')"}
  }
  if (@($Context.rerun_tests | Where-Object { $_ -eq $TestId }).Count -gt 0) {
    return [ordered]@{disposition="RUN"; reason="explicit-rerun"}
  }
  if (-not [bool]$Context.reuse_enabled) {
    return [ordered]@{disposition="RUN"; reason="reuse-disabled"}
  }
  if (Test-MIRAssuranceCanReuseTest -TestId $TestId -Context $Context) {
    $reused = Get-MIRAssuranceReusableEvidence -Fingerprint $Fingerprint -Context $Context -Test $Test
    if ($null -ne $reused) {
      return [ordered]@{disposition="REUSE"; reason="exact-trusted-pass"; evidence=$reused}
    }
    $running = Get-MIRAssuranceRunningEvidence -Fingerprint $Fingerprint -Context $Context
    if ($null -ne $running) {
      return [ordered]@{disposition="WAIT"; reason="matching-worker-in-progress"; running=$running}
    }
  }
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if ((Test-Path -LiteralPath $paths.passed -PathType Leaf) -or (Test-Path -LiteralPath $paths.blocked -PathType Leaf)) {
    return [ordered]@{disposition="INVALID"; reason="stored-evidence-is-not-a-trusted-exact-pass"}
  }
  return [ordered]@{disposition="RUN"; reason="no-exact-evidence"}
}
