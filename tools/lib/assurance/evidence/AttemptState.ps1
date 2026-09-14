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

function Get-MIRAssuranceAttemptIdentity {
  param([Parameter(Mandatory)]$Capsule)
  return [ordered]@{
    test_id=[string]$Capsule.test_id
    input_key=[string]$Capsule.input_key
    target=[string]$Capsule.target
    fingerprint_sha256=[string]$Capsule.fingerprint_sha256
  }
}

function Test-MIRAssuranceExactTrustedAttempt {
  param(
    [Parameter(Mandatory)]$Capsule,
    [Parameter(Mandatory)]$Identity,
    [Parameter(Mandatory)]$Context
  )
  if ([int]$Capsule.schema -ne $evidenceSchema -or
      [string]$Capsule.test_id -ne [string]$Identity.test_id -or
      [string]$Capsule.input_key -ne [string]$Identity.input_key -or
      [string]$Capsule.target -ne [string]$Identity.target -or
      [string]$Capsule.fingerprint_sha256 -ne [string]$Identity.fingerprint_sha256 -or
      [string]$Capsule.status -notin @("passed", "failed") -or
      [string]$Capsule.conclusion -ne [string]$Capsule.status -or
      -not (Test-MIRAssuranceTrustedProducer -Producer $Capsule.producer -Context $Context)) {
    return $false
  }
  return [string]$Capsule.result_digest -eq (Get-MIRAssuranceCapsuleDigest -Capsule $Capsule)
}

function Get-MIRAssuranceTrustedExactAttempts {
  param(
    [Parameter(Mandatory)]$Identity,
    [Parameter(Mandatory)]$Context
  )
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Identity.test_id -InputKey $Identity.input_key
  if (-not (Test-Path -LiteralPath $paths.attempts -PathType Container)) { return @() }
  $attempts = [Collections.Generic.List[object]]::new()
  foreach ($item in @(Get-ChildItem -LiteralPath $paths.attempts -File -Filter '*.json' -ErrorAction Stop | Sort-Object Name)) {
    try { $capsule = Get-Content -Raw -LiteralPath $item.FullName | ConvertFrom-Json }
    catch { continue }
    if (-not (Test-MIRAssuranceExactTrustedAttempt -Capsule $capsule -Identity $Identity -Context $Context)) { continue }
    $attempts.Add([pscustomobject][ordered]@{
      path=(Get-MIRAssuranceRepoRelativePath -Path $item.FullName)
      sha256=(Get-MIRAssuranceSha256 -Path $item.FullName)
      capsule=$capsule
      conclusion=[string]$capsule.conclusion
      result_digest=[string]$capsule.result_digest
    })
  }
  return @($attempts)
}

function Get-MIRAssuranceAttemptQuarantineDirectory {
  param([Parameter(Mandatory)]$Identity)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Identity.test_id -InputKey $Identity.input_key
  return Join-Path $paths.root 'quarantine\incidents'
}

function Get-MIRAssuranceAttemptQuarantineIncidents {
  param([Parameter(Mandatory)]$Identity)
  $directory = Get-MIRAssuranceAttemptQuarantineDirectory -Identity $Identity
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return @() }
  $incidents = [Collections.Generic.List[object]]::new()
  foreach ($item in @(Get-ChildItem -LiteralPath $directory -File -Filter '*.json' -ErrorAction Stop | Sort-Object Name)) {
    try { $incident = Get-Content -Raw -LiteralPath $item.FullName | ConvertFrom-Json -DateKind String }
    catch { continue }
    $incidentMaterial = [ordered]@{
      schema=[int]$incident.schema
      kind=[string]$incident.kind
      status=[string]$incident.status
      identity=$incident.identity
      reason=[string]$incident.reason
      required_action=[string]$incident.required_action
      independent_fresh_reproduction_required=[bool]$incident.independent_fresh_reproduction_required
      attempts=@($incident.attempts)
      created_at=[string]$incident.created_at
    }
    if ([int]$incident.schema -ne 1 -or
        [string]$incident.kind -ne 'mir-assurance-evidence-contradiction-v1' -or
        [string]$incident.status -ne 'quarantined' -or
        [string]$incident.identity.test_id -ne [string]$Identity.test_id -or
        [string]$incident.identity.input_key -ne [string]$Identity.input_key -or
        [string]$incident.identity.target -ne [string]$Identity.target -or
        [string]$incident.identity.fingerprint_sha256 -ne [string]$Identity.fingerprint_sha256 -or
        [string]$incident.incident_sha256 -ne (Get-MIRAssuranceJsonHash -Value $incidentMaterial)) {
      continue
    }
    $incidents.Add([pscustomobject][ordered]@{
      path=(Get-MIRAssuranceRepoRelativePath -Path $item.FullName)
      incident=$incident
    })
  }
  return @($incidents)
}

function Write-MIRAssuranceAttemptQuarantineIncident {
  param(
    [Parameter(Mandatory)]$Identity,
    [Parameter(Mandatory)][AllowEmptyCollection()]$Attempts
  )
  $attemptRows = @(
    foreach ($attempt in @($Attempts | Sort-Object path -Unique)) {
      [ordered]@{
        path=[string]$attempt.path
        sha256=[string]$attempt.sha256
        conclusion=[string]$attempt.conclusion
        result_digest=[string]$attempt.result_digest
        producer=$attempt.capsule.producer
      }
    }
  )
  $incident = [ordered]@{
    schema=1
    kind='mir-assurance-evidence-contradiction-v1'
    status='quarantined'
    identity=$Identity
    reason='trusted-exact-attempt-contradiction'
    required_action='independent-fresh-reproduction-required'
    independent_fresh_reproduction_required=$true
    attempts=$attemptRows
    created_at=[DateTimeOffset]::UtcNow.ToString('o')
  }
  $incident['incident_sha256'] = Get-MIRAssuranceJsonHash -Value $incident
  $directory = Get-MIRAssuranceAttemptQuarantineDirectory -Identity $Identity
  $path = Join-Path $directory ("$($incident.incident_sha256).json")
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    Write-MIRAssuranceAtomicJson -Value $incident -Path $path
  }
  return [pscustomobject][ordered]@{path=(Get-MIRAssuranceRepoRelativePath -Path $path);incident=$incident}
}

function Set-MIRAssuranceAttemptPointer {
  param(
    [Parameter(Mandatory)]$Capsule,
    [Parameter(Mandatory)][string]$AttemptPath,
    [Parameter(Mandatory)]$Context
  )
  $identity = Get-MIRAssuranceAttemptIdentity -Capsule $Capsule
  $paths = Get-MIRAssuranceEvidencePaths -TestId $identity.test_id -InputKey $identity.input_key
  $resolvedAttemptPath = Resolve-MIRAssurancePath -Path $AttemptPath
  $attemptRoot = [IO.Path]::GetFullPath($paths.attempts).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  $resolvedAttempt = [IO.Path]::GetFullPath($resolvedAttemptPath)
  if (-not $resolvedAttempt.StartsWith($attemptRoot, [StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $resolvedAttempt -PathType Leaf) -or
      [string]$Capsule.attempt_path -ne (Get-MIRAssuranceRepoRelativePath -Path $resolvedAttempt)) {
    throw "Assurance attempt pointer must bind the immutable capsule inside its exact attempt subtree."
  }
  $attempts = @(Get-MIRAssuranceTrustedExactAttempts -Identity $identity -Context $Context)
  $conclusions = @($attempts | ForEach-Object { [string]$_.conclusion } | Sort-Object -Unique)
  $digests = @($attempts | ForEach-Object { [string]$_.result_digest } | Sort-Object -Unique)
  $contradiction = $conclusions.Count -gt 1 -or $digests.Count -gt 1
  $incident = $null
  if ($contradiction) {
    $incident = Write-MIRAssuranceAttemptQuarantineIncident -Identity $identity -Attempts $attempts
  }
  $incidents = @(Get-MIRAssuranceAttemptQuarantineIncidents -Identity $identity)
  $pointer = [ordered]@{
    schema=1
    test_id=[string]$identity.test_id
    input_key=[string]$identity.input_key
    conclusion=if ($incidents.Count -gt 0) { 'quarantined' } else { [string]$Capsule.conclusion }
    capsule_path=(Get-MIRAssuranceRepoRelativePath -Path $resolvedAttempt)
    capsule_sha256=(Get-MIRAssuranceSha256 -Path $resolvedAttempt)
  }
  New-Item -ItemType Directory -Force -Path $paths.root | Out-Null
  if ($incidents.Count -gt 0) {
    if (Test-Path -LiteralPath $paths.passed -PathType Leaf) { Remove-Item -LiteralPath $paths.passed -Force }
    Write-MIRAssuranceAtomicJson -Value $pointer -Path $paths.blocked
  } elseif ([string]$Capsule.status -eq 'passed') {
    Write-MIRAssuranceAtomicJson -Value $pointer -Path $paths.passed
    if (Test-Path -LiteralPath $paths.blocked) { Remove-Item -LiteralPath $paths.blocked -Force }
  } else {
    Write-MIRAssuranceAtomicJson -Value $pointer -Path $paths.blocked
  }
  if (Test-Path -LiteralPath $paths.running -PathType Leaf) { Remove-Item -LiteralPath $paths.running -Force }
  return [ordered]@{
    quarantined=($incidents.Count -gt 0)
    incident=if ($null -ne $incident) { [string]$incident.path } elseif ($incidents.Count -gt 0) { [string]$incidents[0].path } else { '' }
    trusted_attempt_count=$attempts.Count
  }
}

function Write-MIRAssuranceAttempt {
  param(
    [Parameter(Mandatory)]$Capsule,
    [Parameter(Mandatory)]$Context
  )
  if (-not $Capsule.Contains('conclusion')) { $Capsule['conclusion'] = [string]$Capsule.status }
  if (-not $Capsule.Contains('producer')) { $Capsule['producer'] = Get-MIRAssuranceProducer }
  $roundTripped = ($Capsule | ConvertTo-Json -Depth 40 -Compress) | ConvertFrom-Json
  $Capsule['result_digest'] = Get-MIRAssuranceCapsuleDigest -Capsule $roundTripped
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Capsule.test_id -InputKey $Capsule.input_key
  New-Item -ItemType Directory -Force -Path $paths.attempts | Out-Null
  $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffffffZ')
  $attemptPath = Join-Path $paths.attempts ("$stamp-$([guid]::NewGuid().ToString('N')).json")
  $Capsule['attempt_path'] = Get-MIRAssuranceRepoRelativePath -Path $attemptPath
  Write-MIRAssuranceAtomicJson -Value $Capsule -Path $attemptPath
  $state = Set-MIRAssuranceAttemptPointer -Capsule $Capsule -AttemptPath $attemptPath -Context $Context
  $Capsule['quarantined'] = [bool]$state.quarantined
  $Capsule['quarantine_incident'] = [string]$state.incident
  return $Capsule
}
