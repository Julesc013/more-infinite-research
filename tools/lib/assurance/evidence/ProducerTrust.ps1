function Get-MIRAssuranceEvidencePaths {
  param([Parameter(Mandatory)][string]$TestId, [Parameter(Mandatory)][string]$InputKey)
  $safeId = $TestId -replace '[^A-Za-z0-9._-]', '_'
  $root = Join-Path $evidenceRoot (Join-Path $safeId $InputKey)
  return [ordered]@{
    root=$root
    attempts=(Join-Path $root "attempts")
    passed=(Join-Path $root "passed.json")
    blocked=(Join-Path $root "blocked.json")
    running=(Join-Path $root "running.json")
  }
}

function Get-MIRAssuranceRepositoryIdentity {
  if (-not [string]::IsNullOrWhiteSpace([string]$env:GITHUB_REPOSITORY)) {
    return [string]$env:GITHUB_REPOSITORY
  }
  $remote = @(& git -C $repo remote get-url origin 2>$null)
  if ($LASTEXITCODE -eq 0 -and $remote.Count -gt 0) {
    $identity = ([string]$remote[0]).Trim()
    $identity = $identity -replace '^git@github\.com:', ''
    $identity = $identity -replace '^https://github\.com/', ''
    $identity = $identity -replace '\.git$', ''
    if ($identity) { return $identity }
  }
  return "local"
}

function Get-MIRAssuranceCurrentTrustClass {
  if ($env:MIR_TRUST_CLASS) { return [string]$env:MIR_TRUST_CLASS }
  if ([string]$env:GITHUB_EVENT_NAME -eq "pull_request" -or [string]$env:GITHUB_EVENT_NAME -eq "pull_request_target") {
    return "untrusted-pr"
  }
  if ($env:GITHUB_ACTIONS) { return "protected-integration" }
  return "untrusted-local"
}

function Get-MIRAssuranceProducer {
  $trustClass = Get-MIRAssuranceCurrentTrustClass
  return [ordered]@{
    repository=(Get-MIRAssuranceRepositoryIdentity)
    workflow=if ($env:GITHUB_WORKFLOW) { [string]$env:GITHUB_WORKFLOW } else { "local" }
    run_id=if ($env:GITHUB_RUN_ID) { [string]$env:GITHUB_RUN_ID } else { "local-$PID" }
    run_attempt=if ($env:GITHUB_RUN_ATTEMPT) { [string]$env:GITHUB_RUN_ATTEMPT } else { "1" }
    job=if ($env:GITHUB_JOB) { [string]$env:GITHUB_JOB } else { "local" }
    actor=if ($env:GITHUB_ACTOR) { [string]$env:GITHUB_ACTOR } else { [Environment]::UserName }
    commit=(& git -C $repo rev-parse HEAD).Trim()
    ref=if ($env:GITHUB_REF) { [string]$env:GITHUB_REF } else { "local" }
    event=if ($env:GITHUB_EVENT_NAME) { [string]$env:GITHUB_EVENT_NAME } else { "local" }
    environment=if ($env:MIR_PROTECTED_ENVIRONMENT) { [string]$env:MIR_PROTECTED_ENVIRONMENT } else { "local" }
    runner_identity=if ($env:MIR_TRUSTED_RUNNER) { [string]$env:MIR_TRUSTED_RUNNER } else { "local" }
    trust_class=$trustClass
    verifier_sha256=(Get-MIRAssuranceRunnerHash)
    policy_sha256=(Get-MIRAssuranceCanonicalJsonFileHash -Path (Get-MIRAssuranceCanonicalTrustPolicyPath))
  }
}

function Get-MIRAssuranceHostIdentity {
  if (-not [string]::IsNullOrWhiteSpace([string]$env:MIR_HOST_IDENTITY)) {
    return [string]$env:MIR_HOST_IDENTITY
  }
  $machine = [Environment]::MachineName
  if (-not [string]::IsNullOrWhiteSpace([string]$env:RUNNER_NAME)) {
    return "github:$([string]$env:RUNNER_NAME)@$machine"
  }
  return "host:$machine"
}

function Get-MIRAssuranceProcessStartedAt {
  param([int]$ProcessId = $PID)
  $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if ($null -eq $process) { return "" }
  return ([DateTimeOffset]$process.StartTime.ToUniversalTime()).ToString("o")
}

function Get-MIRAssuranceEvidenceProducer {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  $producer = ConvertTo-MIRAssuranceOrderedMap -Object (Get-MIRAssuranceProducer)
  if (-not [bool]$Test.force_fresh) { return $producer }

  $campaignId = [string]$Test.required_campaign_id
  $campaignMaterial = [string]$Test.required_campaign_plan_material_sha256
  if ([string]::IsNullOrWhiteSpace($campaignId) -or $campaignMaterial -notmatch '^[A-Fa-f0-9]{64}$') {
    throw "Fresh evidence for '$([string]$Test.id)' is missing its immutable plan-owned campaign identity."
  }
  # A host run is only an execution attempt.  Freshness belongs to the
  # immutable plan campaign so a timeout, runner replacement, or deliberate
  # checkpoint can resume without repeating an already validated row.
  $producer["campaign_id"] = $campaignId
  $producer["campaign_plan_material_sha256"] = $campaignMaterial
  return $producer
}

function Test-MIRAssurancePlanContinuationProducer {
  param(
    [Parameter(Mandatory)]$Producer,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$SourceCommit
  )
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $Producer -Context $Context)) { return $false }
  if ([string]$Producer.commit -ne $SourceCommit) { return $false }
  if ([string]$Context.trust_class -eq "untrusted-local") { return $true }
  $current = Get-MIRAssuranceProducer
  # Run identifiers deliberately do not participate: a new protected worker
  # may continue an unchanged plan.  Its repository, workflow authority,
  # source commit, ref, environment, runner, policy and verifier must match.
  foreach ($field in @("repository", "workflow", "commit", "ref", "event", "trust_class", "environment", "runner_identity", "verifier_sha256", "policy_sha256")) {
    if ([string]$Producer.$field -ne [string]$current.$field) { return $false }
  }
  return $true
}

function Test-MIRAssuranceFreshCampaignEvidence {
  param(
    [Parameter(Mandatory)]$Capsule,
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan
  )
  if (-not [bool]$Test.force_fresh) { return $true }
  try {
    $minimum = ConvertTo-MIRAssuranceDateTimeOffset -Value $Test.minimum_completed_at
    $completed = ConvertTo-MIRAssuranceDateTimeOffset -Value $Capsule.completed_at
  } catch { return $false }
  return $completed -ge $minimum -and
    [string]$Capsule.producer.campaign_id -eq [string]$Test.required_campaign_id -and
    [string]$Capsule.producer.campaign_plan_material_sha256 -eq [string]$Test.required_campaign_plan_material_sha256 -and
    [string]$Capsule.producer.campaign_plan_material_sha256 -eq [string]$Plan.plan_material_sha256 -and
    [string]$Capsule.producer.commit -eq [string]$Plan.source_commit
}

function Test-MIRAssuranceTrustedProducer {
  param([Parameter(Mandatory)]$Producer, [Parameter(Mandatory)]$Context)
  if ($null -eq $Producer) { return $false }
  $repository = [string]$Producer.repository
  if ([string]::IsNullOrWhiteSpace($repository)) { return $false }
  $current = Get-MIRAssuranceRepositoryIdentity
  if ($repository -ne $current -and -not ($repository -eq "local" -and $current -eq "local")) { return $false }
  if ([string]$Producer.trust_class -ne [string]$Context.trust_class) { return $false }
  if ([string]$Producer.verifier_sha256 -ne (Get-MIRAssuranceRunnerHash)) { return $false }
  if ([string]$Producer.policy_sha256 -ne (Get-MIRAssuranceCanonicalJsonFileHash -Path (Get-MIRAssuranceCanonicalTrustPolicyPath))) { return $false }
  return $true
}

function Test-MIRAssuranceReleaseProducer {
  param(
    [Parameter(Mandatory)]$Producer,
    [Parameter(Mandatory)]$Context,
    [string]$ExpectedCommit = "",
    [switch]$AllowAncestor
  )
  if ($null -eq $Producer -or [string]$Producer.trust_class -ne "protected-release") { return $false }
  $class = $Context.trust_policy.classes."protected-release"
  if ($null -eq $class -or $class.release_eligible -ne $true) { return $false }
  if (@($class.repositories | Where-Object { [string]$_ -eq [string]$Producer.repository }).Count -ne 1) { return $false }
  if (@($class.workflows | Where-Object { [string]$_ -eq [string]$Producer.workflow }).Count -ne 1) { return $false }
  if (@($class.events | Where-Object { [string]$_ -eq [string]$Producer.event }).Count -ne 1) { return $false }
  if (@($class.refs | Where-Object { [string]$_ -eq [string]$Producer.ref }).Count -ne 1) { return $false }
  if ([string]$Producer.environment -ne [string]$class.environment) { return $false }
  if ([string]$Producer.runner_identity -ne [string]$class.runner_identity) { return $false }
  if ($AllowAncestor) {
    & git -C $repo merge-base --is-ancestor ([string]$Producer.commit) HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
  } elseif ([string]::IsNullOrWhiteSpace($ExpectedCommit)) {
    $ExpectedCommit = (& git -C $repo rev-parse HEAD).Trim()
    if ([string]$Producer.commit -ne $ExpectedCommit) { return $false }
  } elseif ([string]$Producer.commit -ne $ExpectedCommit) { return $false }
  if ([string]$Producer.verifier_sha256 -ne (Get-MIRAssuranceRunnerHash)) { return $false }
  if ([string]$Producer.policy_sha256 -ne (Get-MIRAssuranceCanonicalJsonFileHash -Path (Get-MIRAssuranceCanonicalTrustPolicyPath))) { return $false }
  return $true
}

function Get-MIRAssuranceCapsuleDigest {
  param([Parameter(Mandatory)]$Capsule)
  $material = [ordered]@{
    schema=[int]$Capsule.schema
    test_id=[string]$Capsule.test_id
    conclusion=[string]$Capsule.conclusion
    input_key=[string]$Capsule.input_key
    fingerprint_sha256=[string]$Capsule.fingerprint_sha256
    definition_sha256=[string]$Capsule.definition_sha256
    target=[string]$Capsule.target
    command=[string]$Capsule.command
    resolved_command=[string]$Capsule.resolved_command
    inputs=$Capsule.inputs
    producer=$Capsule.producer
    assertions=$Capsule.assertions
    exit_code=[int]$Capsule.exit_code
    result=$Capsule.result
    artifacts=$Capsule.artifacts
    stdout_sha256=[string]$Capsule.stdout_sha256
    stderr_sha256=[string]$Capsule.stderr_sha256
    log_digest=[string]$Capsule.log_digest
    started_at=(ConvertTo-MIRAssuranceTimestampText -Value $Capsule.started_at)
    completed_at=(ConvertTo-MIRAssuranceTimestampText -Value $Capsule.completed_at)
    duration_seconds=[double]$Capsule.duration_seconds
    message=[string]$Capsule.message
  }
  return Get-MIRAssuranceJsonHash -Value $material
}
