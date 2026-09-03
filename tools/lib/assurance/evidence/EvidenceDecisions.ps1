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

function Get-MIRAssuranceReusableEvidence {
  param([Parameter(Mandatory)]$Fingerprint, [Parameter(Mandatory)]$Context)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if (-not (Test-Path -LiteralPath $paths.passed -PathType Leaf)) { return $null }
  if (Test-Path -LiteralPath $paths.blocked -PathType Leaf) { return $null }
  $capsule = Read-MIRAssuranceEvidencePointer -Path $paths.passed
  if ($null -eq $capsule) { return $null }
  $validation = Test-MIRAssuranceCapsule -Capsule $capsule -Fingerprint $Fingerprint -Context $Context
  if (-not [bool]$validation.valid) { return $null }
  $result = ConvertTo-MIRAssuranceOrderedMap -Object $capsule
  $result.disposition = "REUSE"
  $result.decision_reason = [string]$validation.reason
  $result.reused_at = (Get-Date).ToUniversalTime().ToString("o")
  $result.source_duration_seconds = [double]$capsule.duration_seconds
  $result.duration_seconds = 0
  $result.evidence_path = Get-MIRAssuranceRepoRelativePath -Path $paths.passed
  return $result
}

function Get-MIRAssuranceCampaignCheckpoint {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  if (-not [bool]$Test.force_fresh) { return $null }
  $checkpoint = Get-MIRAssuranceReusableEvidence -Fingerprint $Test.fingerprint -Context $Context
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
      if ($sameJob -and $hostIdentity -ne (Get-MIRAssuranceHostIdentity)) {
        Remove-Item -LiteralPath $paths.running -Force
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
    [Parameter(Mandatory)][string]$TestId
  )
  $inputMap = if ($null -eq $Fingerprint.inputs) {
    [ordered]@{}
  } else {
    ConvertTo-MIRAssuranceOrderedMap -Object $Fingerprint.inputs
  }
  $missingInputs = @(
    foreach ($inputName in @($inputMap.Keys | Sort-Object)) {
      $inputValue = $inputMap[$inputName]
      if ($null -ne $inputValue -and [string]$inputValue.state -eq "missing") {
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
    $reused = Get-MIRAssuranceReusableEvidence -Fingerprint $Fingerprint -Context $Context
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
