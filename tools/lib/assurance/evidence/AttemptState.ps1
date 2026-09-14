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

# The result digest deliberately authenticates the complete immutable capsule,
# including its producer, work paths, timestamps, durations, logs, and artifact
# descriptors.  Those details distinguish observations, but not their semantic
# conclusion.  Reuse quarantine must compare the latter: two independently
# executed passing observations do not conflict solely because their temporary
# work directories or clocks differ.
function Get-MIRAssuranceOutcomeDigest {
  param([Parameter(Mandatory)]$Capsule)
  $assertionOutcomes = @(
    foreach ($assertion in @($Capsule.assertions | Sort-Object @{Expression={ [string]$_.id }}, @{Expression={ [string]$_.status }})) {
      [ordered]@{
        id=[string]$assertion.id
        status=[string]$assertion.status
      }
    }
  )
  $material = [ordered]@{
    schema='mir-assurance-outcome-v1'
    test_id=[string]$Capsule.test_id
    input_key=[string]$Capsule.input_key
    target=[string]$Capsule.target
    fingerprint_sha256=[string]$Capsule.fingerprint_sha256
    definition_sha256=[string]$Capsule.definition_sha256
    conclusion=[string]$Capsule.conclusion
    status=[string]$Capsule.status
    exit_code=[int]$Capsule.exit_code
    assertions=$assertionOutcomes
  }
  return Get-MIRAssuranceJsonHash -Value $material
}

function Get-MIRAssuranceProducerExecutionIdentity {
  param([Parameter(Mandatory)]$Producer)
  $material = [ordered]@{}
  foreach ($field in @(
    'repository', 'workflow', 'run_id', 'run_attempt', 'job', 'commit', 'ref',
    'event', 'environment', 'runner_identity', 'trust_class', 'verifier_sha256',
    'policy_sha256'
  )) {
    $material[$field] = [string]$Producer.$field
  }
  return Get-MIRAssuranceJsonHash -Value $material
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
  if ([string]$Capsule.result_digest -ne (Get-MIRAssuranceCapsuleDigest -Capsule $Capsule)) {
    return $false
  }
  $derivedOutcomeDigest = Get-MIRAssuranceOutcomeDigest -Capsule $Capsule
  return -not ($null -ne $Capsule.PSObject.Properties['outcome_digest'] -and
    [string]$Capsule.outcome_digest -ne $derivedOutcomeDigest)
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
      outcome_digest=(Get-MIRAssuranceOutcomeDigest -Capsule $capsule)
      producer_execution_identity=(Get-MIRAssuranceProducerExecutionIdentity -Producer $capsule.producer)
    })
  }
  return @($attempts)
}

function Get-MIRAssuranceAttemptQuarantineDirectory {
  param([Parameter(Mandatory)]$Identity)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Identity.test_id -InputKey $Identity.input_key
  return Join-Path $paths.root 'quarantine\incidents'
}

function Get-MIRAssuranceAttemptQuarantineResolutionDirectory {
  param([Parameter(Mandatory)]$Identity)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Identity.test_id -InputKey $Identity.input_key
  return Join-Path $paths.root 'quarantine\resolutions'
}

function Get-MIRAssuranceAttemptStateLockPath {
  param([Parameter(Mandatory)]$Identity)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Identity.test_id -InputKey $Identity.input_key
  return Join-Path $paths.root 'attempt-state.lock'
}

function Enter-MIRAssuranceAttemptStateLock {
  param(
    [Parameter(Mandatory)]$Identity,
    [int]$TimeoutMilliseconds = 15000
  )
  if ($TimeoutMilliseconds -lt 1 -or $TimeoutMilliseconds -gt 60000) {
    throw 'Assurance attempt-state lock timeout must be between 1 and 60000 milliseconds.'
  }
  $path = Get-MIRAssuranceAttemptStateLockPath -Identity $Identity
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  $deadline = [DateTimeOffset]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
  while ($true) {
    try {
      $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
      try {
        $lease = [ordered]@{
          schema=1
          kind='mir-assurance-attempt-state-lock-v1'
          owner_process_id=$PID
          host_identity=(Get-MIRAssuranceHostIdentity)
          acquired_at=[DateTimeOffset]::UtcNow.ToString('o')
          expires_at=[DateTimeOffset]::UtcNow.AddMinutes(2).ToString('o')
        }
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($lease | ConvertTo-Json -Depth 10 -Compress))
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
      } catch {
        $stream.Dispose()
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        throw
      }
      return [pscustomobject][ordered]@{ path=$path; stream=$stream }
    } catch [IO.IOException] {
      # A closed expired lock may be left after a killed process.  Never evict a
      # live exclusive handle; failed removal simply leaves it to time out.
      try {
        $record = Get-Content -Raw -LiteralPath $path -ErrorAction Stop | ConvertFrom-Json -DateKind String
        if ([string]$record.kind -eq 'mir-assurance-attempt-state-lock-v1' -and
            (ConvertTo-MIRAssuranceDateTimeOffset -Value $record.expires_at) -le [DateTimeOffset]::UtcNow) {
          Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
      } catch { }
      if ([DateTimeOffset]::UtcNow -ge $deadline) {
        throw "Timed out acquiring the exact MIR assurance attempt-state lock for '$($Identity.test_id)' / '$($Identity.fingerprint_sha256)'."
      }
      Start-Sleep -Milliseconds 25
    }
  }
}

function Exit-MIRAssuranceAttemptStateLock {
  param([Parameter(Mandatory)]$Lock)
  try { $Lock.stream.Dispose() }
  finally {
    if (Test-Path -LiteralPath ([string]$Lock.path) -PathType Leaf) {
      Remove-Item -LiteralPath ([string]$Lock.path) -Force
    }
  }
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

function Get-MIRAssuranceAttemptQuarantineResolutions {
  param(
    [Parameter(Mandatory)]$Identity,
    [Parameter(Mandatory)]$Context
  )
  $directory = Get-MIRAssuranceAttemptQuarantineResolutionDirectory -Identity $Identity
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return @() }
  $resolutions = [Collections.Generic.List[object]]::new()
  foreach ($item in @(Get-ChildItem -LiteralPath $directory -File -Filter '*.json' -ErrorAction Stop | Sort-Object Name)) {
    try { $resolution = Get-Content -Raw -LiteralPath $item.FullName | ConvertFrom-Json -DateKind String }
    catch { continue }
    $material = [ordered]@{
      schema=[int]$resolution.schema
      kind=[string]$resolution.kind
      status=[string]$resolution.status
      identity=$resolution.identity
      incident_path=[string]$resolution.incident_path
      incident_sha256=[string]$resolution.incident_sha256
      decision=[string]$resolution.decision
      accepted_outcome_digest=[string]$resolution.accepted_outcome_digest
      independent_attempt=$resolution.independent_attempt
      adjudicator=[string]$resolution.adjudicator
      adjudicated_at=[string]$resolution.adjudicated_at
    }
    if ([int]$resolution.schema -ne 1 -or
        [string]$resolution.kind -ne 'mir-assurance-quarantine-resolution-v1' -or
        [string]$resolution.status -ne 'resolved' -or
        [string]$resolution.decision -ne 'accept-independent-fresh-reproduction' -or
        [string]::IsNullOrWhiteSpace([string]$resolution.adjudicator) -or
        [string]$resolution.identity.test_id -ne [string]$Identity.test_id -or
        [string]$resolution.identity.input_key -ne [string]$Identity.input_key -or
        [string]$resolution.identity.target -ne [string]$Identity.target -or
        [string]$resolution.identity.fingerprint_sha256 -ne [string]$Identity.fingerprint_sha256 -or
        [string]$resolution.accepted_outcome_digest -notmatch '^[A-Fa-f0-9]{64}$' -or
        [string]$resolution.resolution_sha256 -ne (Get-MIRAssuranceJsonHash -Value $material)) {
      continue
    }
    $attemptPath = Resolve-MIRAssurancePath -Path ([string]$resolution.independent_attempt.path)
    $attempt = $null
    # Capsule digest canonicalization accepts the normal PowerShell JSON date
    # materialization used when the immutable capsule was written.  Keep that
    # representation here; only incident/resolution timestamps need lexical
    # DateKind String preservation.
    try { $attempt = Get-Content -Raw -LiteralPath $attemptPath -ErrorAction Stop | ConvertFrom-Json }
    catch { continue }
    if (-not (Test-MIRAssuranceExactTrustedAttempt -Capsule $attempt -Identity $Identity -Context $Context) -or
        (Get-MIRAssuranceSha256 -Path $attemptPath) -ne [string]$resolution.independent_attempt.sha256 -or
        (Get-MIRAssuranceOutcomeDigest -Capsule $attempt) -ne [string]$resolution.independent_attempt.outcome_digest -or
        [string]$attempt.result_digest -ne [string]$resolution.independent_attempt.result_digest -or
        (Get-MIRAssuranceProducerExecutionIdentity -Producer $attempt.producer) -ne [string]$resolution.independent_attempt.producer_execution_identity) {
      continue
    }
    $resolutions.Add([pscustomobject][ordered]@{
      path=(Get-MIRAssuranceRepoRelativePath -Path $item.FullName)
      resolution=$resolution
      capsule=$attempt
    })
  }
  return @($resolutions)
}

function Get-MIRAssuranceAttemptQuarantineState {
  param(
    [Parameter(Mandatory)]$Identity,
    [Parameter(Mandatory)]$Context
  )
  $incidents = @(Get-MIRAssuranceAttemptQuarantineIncidents -Identity $Identity)
  $resolutions = @(Get-MIRAssuranceAttemptQuarantineResolutions -Identity $Identity -Context $Context)
  $unresolved = [Collections.Generic.List[object]]::new()
  $resolved = [Collections.Generic.List[object]]::new()
  foreach ($incidentRow in $incidents) {
    $incident = $incidentRow.incident
    $validResolution = $null
    foreach ($resolutionRow in $resolutions) {
      $resolution = $resolutionRow.resolution
      if ([string]$resolution.incident_path -ne [string]$incidentRow.path -or
          [string]$resolution.incident_sha256 -ne [string]$incident.incident_sha256) {
        continue
      }
      $attemptRows = @($incident.attempts)
      $independent = $resolution.independent_attempt
      $incidentProducerIdentities = @($attemptRows | ForEach-Object { [string]$_.producer_execution_identity } | Sort-Object -Unique)
      $incidentOutcomeDigests = @($attemptRows | ForEach-Object { [string]$_.outcome_digest } | Sort-Object -Unique)
      try {
        $incidentCreatedAt = ConvertTo-MIRAssuranceDateTimeOffset -Value $incident.created_at
        $attemptCompletedAt = ConvertTo-MIRAssuranceDateTimeOffset -Value $resolutionRow.capsule.completed_at
      } catch { continue }
      if ($attemptCompletedAt -le $incidentCreatedAt -or
          $incidentProducerIdentities -contains [string]$independent.producer_execution_identity -or
          $incidentOutcomeDigests -notcontains [string]$independent.outcome_digest -or
          [string]$resolution.accepted_outcome_digest -ne [string]$independent.outcome_digest) {
        continue
      }
      $validResolution = $resolutionRow
      break
    }
    if ($null -eq $validResolution) { $unresolved.Add($incidentRow) }
    else {
      $resolved.Add([pscustomobject][ordered]@{ incident=$incidentRow; resolution=$validResolution })
    }
  }
  return [pscustomobject][ordered]@{
    incidents=$incidents
    resolutions=$resolutions
    unresolved_incidents=@($unresolved)
    resolved_incidents=@($resolved)
  }
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
        outcome_digest=[string]$attempt.outcome_digest
        producer_execution_identity=[string]$attempt.producer_execution_identity
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
  $attemptMaterialSha256 = Get-MIRAssuranceJsonHash -Value $attemptRows
  foreach ($existing in @(Get-MIRAssuranceAttemptQuarantineIncidents -Identity $Identity)) {
    $existingKeys = @($existing.incident.attempts | ForEach-Object { "$([string]$_.path):$([string]$_.sha256)" })
    $currentKeys = @($attemptRows | ForEach-Object { "$([string]$_.path):$([string]$_.sha256)" })
    $existingRemainsPresent = $existingKeys.Count -ge 2 -and @($existingKeys | Where-Object { $_ -notin $currentKeys }).Count -eq 0
    if ((Get-MIRAssuranceJsonHash -Value @($existing.incident.attempts)) -eq $attemptMaterialSha256 -or $existingRemainsPresent) {
      return $existing
    }
  }
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
    [Parameter(Mandatory)]$Context,
    [int]$LockTimeoutMilliseconds = 15000
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
  $lock = Enter-MIRAssuranceAttemptStateLock -Identity $identity -TimeoutMilliseconds $LockTimeoutMilliseconds
  try {
    # The state lock covers the exact trusted scan, immutable incident write,
    # resolution read, and mutable pointer update.  Worker imports call this
    # same function, so an importer cannot race a local executor into a pass.
    $attempts = @(Get-MIRAssuranceTrustedExactAttempts -Identity $identity -Context $Context)
    $conclusions = @($attempts | ForEach-Object { [string]$_.conclusion } | Sort-Object -Unique)
    $outcomes = @($attempts | ForEach-Object { [string]$_.outcome_digest } | Sort-Object -Unique)
    $contradiction = $conclusions.Count -gt 1 -or $outcomes.Count -gt 1
    $incident = $null
    if ($contradiction) {
      $incident = Write-MIRAssuranceAttemptQuarantineIncident -Identity $identity -Attempts $attempts
    }
    $quarantineState = Get-MIRAssuranceAttemptQuarantineState -Identity $identity -Context $Context
    $unresolved = @($quarantineState.unresolved_incidents)
    $currentPath = Get-MIRAssuranceRepoRelativePath -Path $resolvedAttempt
    $currentSha256 = Get-MIRAssuranceSha256 -Path $resolvedAttempt
    $pointer = [ordered]@{
      schema=1
      test_id=[string]$identity.test_id
      input_key=[string]$identity.input_key
      conclusion=if ($unresolved.Count -gt 0) { 'quarantined' } else { [string]$Capsule.conclusion }
      capsule_path=$currentPath
      capsule_sha256=$currentSha256
    }
    if ($unresolved.Count -gt 0) {
      $activeIncident = $unresolved[0]
      $opposite = @(
        $attempts | Where-Object {
          [string]$_.conclusion -ne [string]$Capsule.conclusion -or
          [string]$_.outcome_digest -ne (Get-MIRAssuranceOutcomeDigest -Capsule $Capsule)
        } | Sort-Object path
      ) | Select-Object -First 1
      $pointer['incident_path'] = [string]$activeIncident.path
      $pointer['incident_sha256'] = [string]$activeIncident.incident.incident_sha256
      $pointer['current_capsule_path'] = $currentPath
      $pointer['current_capsule_sha256'] = $currentSha256
      if ($null -ne $opposite) {
        # Point at the opposite immutable observation so the failure readback is
        # diagnostic rather than accidentally presenting the newest pass.
        $pointer['capsule_path'] = [string]$opposite.path
        $pointer['capsule_sha256'] = [string]$opposite.sha256
        $pointer['opposite_capsule_path'] = [string]$opposite.path
        $pointer['opposite_capsule_sha256'] = [string]$opposite.sha256
        $pointer['opposite_outcome_digest'] = [string]$opposite.outcome_digest
      }
    }
    New-Item -ItemType Directory -Force -Path $paths.root | Out-Null
    if ($unresolved.Count -gt 0) {
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
      quarantined=($unresolved.Count -gt 0)
      incident=if ($null -ne $incident) { [string]$incident.path } elseif ($unresolved.Count -gt 0) { [string]$unresolved[0].path } else { '' }
      trusted_attempt_count=$attempts.Count
    }
  } finally {
    Exit-MIRAssuranceAttemptStateLock -Lock $lock
  }
}

function Resolve-MIRAssuranceAttemptQuarantine {
  param(
    [Parameter(Mandatory)]$Identity,
    [Parameter(Mandatory)][string]$IndependentAttemptPath,
    [Parameter(Mandatory)][string]$Adjudicator,
    [Parameter(Mandatory)]$Context
  )
  if ([string]::IsNullOrWhiteSpace($Adjudicator)) {
    throw 'Quarantine resolution requires a non-empty independent adjudicator identity.'
  }
  $exactIdentity = [ordered]@{
    test_id=[string]$Identity.test_id
    input_key=[string]$Identity.input_key
    target=[string]$Identity.target
    fingerprint_sha256=[string]$Identity.fingerprint_sha256
  }
  $lock = Enter-MIRAssuranceAttemptStateLock -Identity $exactIdentity
  try {
    $attempts = @(Get-MIRAssuranceTrustedExactAttempts -Identity $exactIdentity -Context $Context)
    $selected = @($attempts | Where-Object { [string]$_.path -eq [string]$IndependentAttemptPath })
    if ($selected.Count -ne 1) {
      throw 'Quarantine resolution requires one trusted immutable attempt inside the exact attempt subtree.'
    }
    $selected = $selected[0]
    if ([string]$selected.conclusion -ne 'passed') {
      throw 'Quarantine resolution may only establish a reusable passed pointer from an independent passing reproduction.'
    }
    $state = Get-MIRAssuranceAttemptQuarantineState -Identity $exactIdentity -Context $Context
    if (@($state.unresolved_incidents).Count -eq 0) {
      throw 'Quarantine resolution requires an unresolved exact contradiction incident.'
    }
    $written = [Collections.Generic.List[object]]::new()
    foreach ($incidentRow in @($state.unresolved_incidents)) {
      $incident = $incidentRow.incident
      $incidentProducerIdentities = @($incident.attempts | ForEach-Object { [string]$_.producer_execution_identity } | Sort-Object -Unique)
      $incidentOutcomeDigests = @($incident.attempts | ForEach-Object { [string]$_.outcome_digest } | Sort-Object -Unique)
      try {
        $incidentCreatedAt = ConvertTo-MIRAssuranceDateTimeOffset -Value $incident.created_at
        $selectedCompletedAt = ConvertTo-MIRAssuranceDateTimeOffset -Value $selected.capsule.completed_at
      } catch { throw 'Quarantine incident or selected independent reproduction has no valid completion time.' }
      if ($selectedCompletedAt -le $incidentCreatedAt) {
        throw 'Quarantine resolution requires fresh evidence completed after the contradiction incident.'
      }
      if ($incidentProducerIdentities -contains [string]$selected.producer_execution_identity) {
        throw 'Quarantine resolution requires an independent producer execution identity; a normal same-worker retry cannot clear the incident.'
      }
      if ($incidentOutcomeDigests -notcontains [string]$selected.outcome_digest) {
        throw 'Quarantine resolution must adjudicate one of the recorded contradictory outcomes.'
      }
      $resolution = [ordered]@{
        schema=1
        kind='mir-assurance-quarantine-resolution-v1'
        status='resolved'
        identity=$exactIdentity
        incident_path=[string]$incidentRow.path
        incident_sha256=[string]$incident.incident_sha256
        decision='accept-independent-fresh-reproduction'
        accepted_outcome_digest=[string]$selected.outcome_digest
        independent_attempt=[ordered]@{
          path=[string]$selected.path
          sha256=[string]$selected.sha256
          result_digest=[string]$selected.result_digest
          outcome_digest=[string]$selected.outcome_digest
          producer_execution_identity=[string]$selected.producer_execution_identity
        }
        adjudicator=$Adjudicator
        adjudicated_at=[DateTimeOffset]::UtcNow.ToString('o')
      }
      $resolution['resolution_sha256'] = Get-MIRAssuranceJsonHash -Value $resolution
      $directory = Get-MIRAssuranceAttemptQuarantineResolutionDirectory -Identity $exactIdentity
      $path = Join-Path $directory ("$($resolution.resolution_sha256).json")
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-MIRAssuranceAtomicJson -Value $resolution -Path $path
      }
      $written.Add([pscustomobject][ordered]@{path=(Get-MIRAssuranceRepoRelativePath -Path $path);resolution=$resolution})
    }
  } finally {
    Exit-MIRAssuranceAttemptStateLock -Lock $lock
  }
  # Re-enter through the canonical atomic pointer writer after the resolution
  # record exists.  This keeps pointer effects and worker-import behavior
  # identical to normal local evidence.
  $selectedPath = Resolve-MIRAssurancePath -Path ([string]$selected.path)
  $pointerState = Set-MIRAssuranceAttemptPointer -Capsule $selected.capsule -AttemptPath $selectedPath -Context $Context
  if ([bool]$pointerState.quarantined) {
    throw 'Independent quarantine resolution did not clear every exact unresolved contradiction.'
  }
  return [ordered]@{
    status='resolved'
    resolutions=@($written)
    capsule_path=[string]$selected.path
    outcome_digest=[string]$selected.outcome_digest
  }
}

function Write-MIRAssuranceAttempt {
  param(
    [Parameter(Mandatory)]$Capsule,
    [Parameter(Mandatory)]$Context
  )
  if (-not $Capsule.Contains('conclusion')) { $Capsule['conclusion'] = [string]$Capsule.status }
  if (-not $Capsule.Contains('producer')) { $Capsule['producer'] = Get-MIRAssuranceProducer }
  $Capsule['outcome_digest'] = Get-MIRAssuranceOutcomeDigest -Capsule $Capsule
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
