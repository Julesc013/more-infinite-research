function Write-MIRAssuranceRunningEvidence {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context,
    $Plan = $null,
    $Test = $null
  )
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  New-Item -ItemType Directory -Force -Path $paths.root | Out-Null
  $ttl = [int]$Context.verification_profile.running_evidence_ttl_minutes
  if ($ttl -le 0) { $ttl = 360 }
  $producer = Get-MIRAssuranceProducer
  $leaseScope = if ($env:GITHUB_ACTIONS) { "ci-job" } else { "process" }
  $running = [ordered]@{
    schema=2
    test_id=[string]$Fingerprint.test_id
    input_key=[string]$Fingerprint.input_key
    fingerprint_sha256=[string]$Fingerprint.fingerprint_sha256
    target=[string]$Fingerprint.target
    producer=$producer
    lease_scope=$leaseScope
    host_identity=(Get-MIRAssuranceHostIdentity)
    process_id=$PID
    process_started_at=(Get-MIRAssuranceProcessStartedAt)
    workflow_run_id=[string]$producer.run_id
    workflow_run_attempt=[string]$producer.run_attempt
    workflow_job=[string]$producer.job
    started_at=[DateTimeOffset]::UtcNow.ToString("o")
    expires_at=[DateTimeOffset]::UtcNow.AddMinutes($ttl).ToString("o")
  }
  if ($null -ne $Plan -and $null -ne $Test -and [bool]$Test.force_fresh) {
    $running["campaign_id"] = [string]$Test.required_campaign_id
    $running["campaign_plan_material_sha256"] = [string]$Test.required_campaign_plan_material_sha256
  }
  Write-MIRAssuranceAtomicJson -Value $running -Path $paths.running
  return $running
}

function Remove-MIRAssuranceRunningEvidence {
  param([Parameter(Mandatory)]$Fingerprint)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if (Test-Path -LiteralPath $paths.running -PathType Leaf) { Remove-Item -LiteralPath $paths.running -Force }
}

function Write-MIRAssuranceAttempt {
  param([Parameter(Mandatory)]$Capsule)
  if (-not $Capsule.Contains("conclusion")) { $Capsule["conclusion"] = [string]$Capsule.status }
  if (-not $Capsule.Contains("producer")) { $Capsule["producer"] = Get-MIRAssuranceProducer }
  $roundTripped = ($Capsule | ConvertTo-Json -Depth 40 -Compress) | ConvertFrom-Json
  $Capsule["result_digest"] = Get-MIRAssuranceCapsuleDigest -Capsule $roundTripped
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Capsule.test_id -InputKey $Capsule.input_key
  New-Item -ItemType Directory -Force -Path $paths.attempts | Out-Null
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffffffZ")
  $attemptPath = Join-Path $paths.attempts ("$stamp-$([guid]::NewGuid().ToString('N')).json")
  $Capsule["attempt_path"] = Get-MIRAssuranceRepoRelativePath -Path $attemptPath
  Write-MIRAssuranceAtomicJson -Value $Capsule -Path $attemptPath
  $pointer = [ordered]@{
    schema=1
    test_id=[string]$Capsule.test_id
    input_key=[string]$Capsule.input_key
    conclusion=[string]$Capsule.conclusion
    capsule_path=(Get-MIRAssuranceRepoRelativePath -Path $attemptPath)
    capsule_sha256=(Get-MIRAssuranceSha256 -Path $attemptPath)
  }
  New-Item -ItemType Directory -Force -Path $paths.root | Out-Null
  if ([string]$Capsule.status -eq "passed") {
    Write-MIRAssuranceAtomicJson -Value $pointer -Path $paths.passed
    if (Test-Path -LiteralPath $paths.blocked) { Remove-Item -LiteralPath $paths.blocked -Force }
  } else {
    Write-MIRAssuranceAtomicJson -Value $pointer -Path $paths.blocked
  }
  if (Test-Path -LiteralPath $paths.running -PathType Leaf) { Remove-Item -LiteralPath $paths.running -Force }
  return $Capsule
}
