function Add-MIRAssurancePlanDecisions {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  $decorated = @()
  $work = @()
  foreach ($testValue in @($Plan.tests)) {
    $test = ConvertTo-MIRAssuranceOrderedMap -Object $testValue
    if (-not $test.Contains("safe_test_id") -or [string]::IsNullOrWhiteSpace([string]$test.safe_test_id)) {
      $test["safe_test_id"] = ([string]$test.id -replace '[^A-Za-z0-9._-]', '_')
    }
    if ($env:MIR_ASSURANCE_TIMING) { Write-Host "[assurance-timing] fingerprint $($test.id) start" }
    $fingerprint = Get-MIRAssuranceTestFingerprint -Test $test -Plan $Plan -Context $Context
    if ($env:MIR_ASSURANCE_TIMING) { Write-Host "[assurance-timing] fingerprint $($test.id) done" }
    $decision = Get-MIRAssuranceEvidenceDecision -Fingerprint $fingerprint -Context $Context -TestId ([string]$test.id)
    $test["fingerprint"] = $fingerprint
    $test["disposition"] = [string]$decision.disposition
    $test["decision_reason"] = [string]$decision.reason
    $decorated += [pscustomobject]$test
    if ([string]$decision.disposition -ne "REUSE") {
      $work += [pscustomobject][ordered]@{
        test_id=[string]$test.id
        safe_test_id=[string]$test.safe_test_id
        fingerprint=[string]$fingerprint.fingerprint_sha256
        disposition=[string]$decision.disposition
        layer=[string]$test.layer
      }
    }
  }
  $Plan.tests = @($decorated)
  $Plan["work"] = @($work)
  $Plan["counts"] = [ordered]@{
    total=$decorated.Count
    reuse=@($decorated | Where-Object disposition -eq "REUSE").Count
    wait=@($decorated | Where-Object disposition -eq "WAIT").Count
    run=@($decorated | Where-Object disposition -eq "RUN").Count
    invalid=@($decorated | Where-Object disposition -eq "INVALID").Count
  }
  return $Plan
}

function Get-MIRAssurancePlanMaterial {
  param([Parameter(Mandatory)]$Plan)
  $tests = @(
    foreach ($test in @($Plan.tests | Sort-Object id)) {
      [ordered]@{
        id=[string]$test.id
        layer=[string]$test.layer
        definition_sha256=[string]$test.fingerprint.definition_sha256
        fingerprint_sha256=[string]$test.fingerprint.fingerprint_sha256
      }
    }
  )
  return [ordered]@{
    schema=4
    policy_id=[string]$Plan.policy_id
    target=[string]$Plan.target
    profile=[string]$Plan.profile
    baseline=[string]$Plan.baseline
    source_commit=[string]$Plan.source_commit
    source_tree=[string]$Plan.source_tree
    candidate_descriptor_sha256=[string]$Plan.candidate_descriptor.descriptor_sha256
    package_source_sha256=[string]$Plan.package_source_sha256
    digest_policy_ids=[ordered]@{
      text=[string]$Plan.digest_policy_ids.text
      json=[string]$Plan.digest_policy_ids.json
    }
    catalog_sha256=[string]$Plan.test_catalog_sha256
    validation_harness_sha256=[string]$Plan.validation_harness_sha256
    verification_profile_sha256=[string]$Plan.verification_profile_sha256
    domain_policy_sha256=[string]$Plan.domain_policy_sha256
    trust_policy_sha256=[string]$Plan.trust_policy_sha256
    expected_test_ids=@($Plan.expected_test_ids | ForEach-Object { [string]$_ })
    required_test_set_sha256=[string]$Plan.required_test_set_sha256
    reuse_enabled=[bool]$Plan.reuse_enabled
    rerun_tests=@($Plan.rerun_tests | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    tests=$tests
  }
}

function Complete-MIRAssurancePlan {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  $expectedIds = @($Plan.tests | ForEach-Object { [string]$_.id } | Sort-Object)
  $duplicates = @($expectedIds | Group-Object | Where-Object Count -gt 1)
  if ($duplicates.Count -gt 0) { throw "Verification plan contains duplicate tests: $($duplicates.Name -join ', ')" }
  if ($expectedIds.Count -eq 0) { throw "Verification plan cannot be empty." }
  $Plan["expected_test_ids"] = $expectedIds
  $Plan["required_test_set_sha256"] = Get-MIRAssuranceJsonHash -Value $expectedIds
  $Plan["catalog_sha256"] = [string]$Plan.test_catalog_sha256
  $Plan["policy_sha256"] = Get-MIRAssuranceJsonHash -Value ([ordered]@{
    assurance=(Get-MIRAssuranceCanonicalJsonFileHash -Path $configPath)
    domains=[string]$Plan.domain_policy_sha256
    profile=[string]$Plan.verification_profile_sha256
    trust=[string]$Plan.trust_policy_sha256
  })
  $Plan["candidate_descriptor_sha256"] = [string]$Plan.candidate_descriptor.descriptor_sha256
  $producer = $Plan.producer
  if ($null -eq $producer) {
    $producer = Get-MIRAssuranceProducer
    $Plan["producer"] = $producer
  }
  # Plan material deliberately excludes execution time and host identity.  It
  # is therefore a stable campaign namespace for this exact source, candidate,
  # policy and test set.  minimum_completed_at still prevents a later fresh
  # campaign from adopting an older result with the same inputs.
  $Plan["plan_material_sha256"] = Get-MIRAssuranceJsonHash -Value (Get-MIRAssurancePlanMaterial -Plan $Plan)
  $Plan["campaign"] = [ordered]@{
    schema="mir-assurance-campaign-v1"
    id="plan-$(([string]$Plan.plan_material_sha256).ToLowerInvariant())"
    plan_material_sha256=[string]$Plan.plan_material_sha256
    created_at=[string]$Plan.generated_at
  }
  foreach ($test in @($Plan.tests)) {
    $forceFresh = (-not [bool]$Plan.reuse_enabled) -or @($Plan.rerun_tests | Where-Object { [string]$_ -eq [string]$test.id }).Count -gt 0
    $test | Add-Member -NotePropertyName force_fresh -NotePropertyValue $forceFresh -Force
    if ($forceFresh) {
      $test | Add-Member -NotePropertyName minimum_completed_at -NotePropertyValue ([string]$Plan.generated_at) -Force
      $test | Add-Member -NotePropertyName required_campaign_id -NotePropertyValue ([string]$Plan.campaign.id) -Force
      $test | Add-Member -NotePropertyName required_campaign_plan_material_sha256 -NotePropertyValue ([string]$Plan.plan_material_sha256) -Force
    }
  }
  return $Plan
}

function Get-MIRAssuranceReconstructionArgs {
  param([Parameter(Mandatory)]$Plan)
  $filtered = @()
  $takesValue = @("--plan", "--profile", "--baseline", "--rerun", "--target", "--candidate", "--factorio", "--prior", "--seal", "--mods", "--output", "--test", "--fingerprint")
  for ($i = 0; $i -lt $script:Args.Count; $i++) {
    $arg = [string]$script:Args[$i]
    if ($takesValue -contains $arg) { $i++; continue }
    if ($arg -eq "--no-reuse") { continue }
    $filtered += $arg
  }
  $filtered += @("--profile", [string]$Plan.profile)
  if (-not [string]::IsNullOrWhiteSpace([string]$Plan.baseline)) { $filtered += @("--baseline", [string]$Plan.baseline) }
  foreach ($testId in @($Plan.rerun_tests)) { $filtered += @("--rerun", [string]$testId) }
  if (-not [bool]$Plan.reuse_enabled) { $filtered += "--no-reuse" }
  return @($filtered)
}

function Assert-MIRAssurancePlanFreshnessBinding {
  param(
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  if ($null -eq $Plan.campaign -or
      [string]$Plan.campaign.schema -ne "mir-assurance-campaign-v1" -or
      [string]$Plan.campaign.id -ne "plan-$(([string]$Plan.plan_material_sha256).ToLowerInvariant())" -or
      [string]$Plan.campaign.plan_material_sha256 -ne [string]$Plan.plan_material_sha256 -or
      [string]$Plan.campaign.created_at -ne [string]$Plan.generated_at) {
    throw "Verification plan campaign identity is missing or was altered."
  }
  if (-not (Test-MIRAssurancePlanContinuationProducer -Producer $Plan.producer -Context $Context -SourceCommit ([string]$Plan.source_commit))) {
    throw "Verification plan producer is not an authorized continuation of the plan source and trust context."
  }
  foreach ($test in @($Plan.tests)) {
    $forceFresh = (-not [bool]$Plan.reuse_enabled) -or
      @($Plan.rerun_tests | Where-Object { [string]$_ -eq [string]$test.id }).Count -gt 0
    if ([bool]$test.force_fresh -ne $forceFresh) {
      throw "Verification plan freshness policy was altered for '$([string]$test.id)'."
    }
    if ($forceFresh) {
      if ([string]$test.minimum_completed_at -ne [string]$Plan.generated_at -or
          [string]$test.required_campaign_id -ne [string]$Plan.campaign.id -or
          [string]$test.required_campaign_plan_material_sha256 -ne [string]$Plan.plan_material_sha256) {
        throw "Verification plan fresh-evidence binding was altered for '$([string]$test.id)'."
      }
    }
  }
  return $Plan
}

function Assert-MIRAssurancePlan {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  if ([int]$Plan.schema -ne 4) { throw "Verification plan schema must be 4." }
  if ([string]$Plan.target -ne [string]$Context.target) { throw "Verification plan target does not match --target." }
  if ([string]::IsNullOrWhiteSpace([string]$Plan.profile)) { throw "Verification plan profile is missing." }
  $ids = @($Plan.tests | ForEach-Object { [string]$_.id })
  if ($ids.Count -eq 0) { throw "Verification plan cannot be empty." }
  $duplicates = @($ids | Group-Object | Where-Object Count -gt 1)
  if ($duplicates.Count -gt 0) { throw "Verification plan contains duplicate tests: $($duplicates.Name -join ', ')" }
  if (@(Compare-Object @($Plan.expected_test_ids | Sort-Object) @($ids | Sort-Object)).Count -gt 0) {
    throw "Verification plan test rows differ from expected_test_ids."
  }
  if ([string]$Plan.required_test_set_sha256 -ne (Get-MIRAssuranceJsonHash -Value @($Plan.expected_test_ids | ForEach-Object { [string]$_ }))) {
    throw "Verification plan required-test-set digest is invalid."
  }
  if ([string]$Plan.plan_material_sha256 -ne (Get-MIRAssuranceJsonHash -Value (Get-MIRAssurancePlanMaterial -Plan $Plan))) {
    throw "Verification plan material digest is invalid."
  }
  $null = Assert-MIRAssurancePlanFreshnessBinding -Plan $Plan -Context $Context

  $originalArgs = @($script:Args)
  $expectedContext = $Context.PSObject.Copy()
  $expectedContext.reuse_enabled = [bool]$Plan.reuse_enabled
  $expectedContext.rerun_tests = @($Plan.rerun_tests | ForEach-Object { [string]$_ })
  try {
    $script:Args = @(Get-MIRAssuranceReconstructionArgs -Plan $Plan)
    $expected = Get-MIRAssurancePlan -Context $expectedContext
  } finally {
    $script:Args = $originalArgs
  }
  if ([string]$expected.plan_material_sha256 -ne [string]$Plan.plan_material_sha256) {
    throw "Verification plan does not match the canonical profile, catalog, inputs, candidate, source, or policy."
  }
  return $Plan
}

function Get-MIRAssurancePlanFromOption {
  param([Parameter(Mandatory)]$Context, [switch]$RequirePlan)
  $planOption = Get-MIRAssuranceOption -Name "--plan"
  if ($planOption) {
    $path = Resolve-MIRAssurancePath -Path $planOption
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Verification plan not found: $path" }
    $plan = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    $validatedPlan = Assert-MIRAssurancePlan -Plan $plan -Context $Context
    Sync-MIRAssuranceContextFromPlan -Context $Context -Plan $validatedPlan
    return $validatedPlan
  }
  if ($RequirePlan) { throw "This command requires --plan <verification-plan.json>." }
  return Get-MIRAssurancePlan -Context $Context
}

function Sync-MIRAssuranceContextFromPlan {
  param(
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Plan
  )
  $Context.reuse_enabled = [bool]$Plan.reuse_enabled
  $Context.rerun_tests = @($Plan.rerun_tests | ForEach-Object { [string]$_ })
}

function Get-MIRAssurancePlannedTest {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$TestId)
  if ([string]::IsNullOrWhiteSpace($TestId)) { throw "--test <stable-id> is required." }
  $matches = @($Plan.tests | Where-Object { [string]$_.id -eq $TestId })
  if ($matches.Count -ne 1) { throw "Verification plan does not contain exactly one test '$TestId'." }
  return $matches[0]
}
