function Wait-MIRAssuranceEvidence {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context,
    [int]$PollSeconds = 5
  )
  while ($true) {
    $reused = Get-MIRAssuranceReusableEvidence -Fingerprint $Fingerprint -Context $Context
    if ($null -ne $reused) { return $reused }
    $running = Get-MIRAssuranceRunningEvidence -Fingerprint $Fingerprint -Context $Context
    if ($null -eq $running) { return $null }
    Start-Sleep -Seconds $PollSeconds
  }
}

function Get-MIRAssuranceArtifactDescriptor {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Kind
  )
  $resolved = Resolve-MIRAssurancePath -Path $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "Required assurance artifact does not exist: $resolved"
  }
  $item = Get-Item -LiteralPath $resolved
  return [ordered]@{
    kind=$Kind
    path=(Get-MIRAssuranceRepoRelativePath -Path $item.FullName)
    bytes=$item.Length
    sha256=(Get-MIRAssuranceSha256 -Path $item.FullName)
  }
}

function Get-MIRAssuranceScenarioResult {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)][string]$SummaryPath
  )
  if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
    throw "Scenario worker did not create its structured validation summary: $SummaryPath"
  }
  try { $summary = Get-Content -Raw -LiteralPath $SummaryPath | ConvertFrom-Json }
  catch { throw "Scenario worker summary is invalid JSON: $SummaryPath" }
  if ([int]$summary.schema -ne 2 -or [string]$summary.status -ne "passed") {
    throw "Scenario worker summary is not a passing schema-2 result."
  }
  $scenarioName = [string]$Test.scenario.name
  $expected = @($summary.expected_scenarios | ForEach-Object { [string]$_ })
  $scenarios = @($summary.scenarios | Where-Object { [string]$_.name -eq $scenarioName })
  if ($expected.Count -ne 1 -or $expected[0] -ne $scenarioName -or $scenarios.Count -ne 1) {
    throw "Scenario worker summary does not contain exactly the planned scenario '$scenarioName'."
  }
  $scenario = $scenarios[0]
  $declaredAssertions = @($Test.scenario.assertions)
  if ([string]$scenario.status -ne "passed" -or
      [int]$scenario.assertions_executed -lt $declaredAssertions.Count -or
      $declaredAssertions.Count -eq 0) {
    throw "Scenario '$scenarioName' did not report all declared assertions as executed and passing."
  }
  $summaryDescriptor = Get-MIRAssuranceArtifactDescriptor -Path $SummaryPath -Kind "validation-summary"
  $assertions = @(
    foreach ($assertion in $declaredAssertions) {
      [ordered]@{
        id=[string]$assertion.id
        status="passed"
        evidence=[string]$summaryDescriptor.path
      }
    }
  )
  return [ordered]@{
    assertions=$assertions
    artifacts=@($summaryDescriptor)
  }
}

function Invoke-MIRAssuranceTest {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
  $id = [string]$Test.id
  if ([bool]$Test.requires_factorio -and (-not $Context.factorio -or -not (Test-Path -LiteralPath $Context.factorio -PathType Leaf))) {
    throw "Test $id requires --factorio with a matching Factorio binary."
  }
  if ($id -eq "runtime.upgrade" -and (-not $Context.prior_release -or -not (Test-Path -LiteralPath $Context.prior_release -PathType Leaf))) {
    throw "Test runtime.upgrade requires --prior with the exact prior-release archive."
  }
  if ([bool]$Test.requires_candidate -or @($Test.inputs | Where-Object { [string]$_ -eq "candidate" }).Count -gt 0) {
    if (-not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) {
      throw "Test $id requires the exact candidate archive: $($Context.candidate)"
    }
  }

  $fingerprint = if ($Test.fingerprint) { $Test.fingerprint } else { Get-MIRAssuranceTestFingerprint -Test $Test -Plan $Plan -Context $Context }
  # Fresh campaigns do not reuse arbitrary historical evidence.  They do,
  # however, adopt a cryptographically exact row that was completed for this
  # same immutable campaign before an interruption.  That makes the boundary
  # between process attempts recoverable without weakening the release gate.
  $checkpoint = Get-MIRAssuranceCampaignCheckpoint -Test $Test -Plan $Plan -Context $Context
  if ($null -ne $checkpoint) {
    Write-Host "[CHECKPOINT] $id $($fingerprint.input_key)"
    return $checkpoint
  }
  if ([bool]$Test.force_fresh) {
    $running = Get-MIRAssuranceRunningEvidence -Fingerprint $fingerprint -Context $Context
    if ($null -ne $running) {
      Write-Host "[WAIT] $id $($fingerprint.input_key)"
      $adopted = Wait-MIRAssuranceEvidence -Fingerprint $fingerprint -Context $Context
      if ($null -ne $adopted) {
        $checkpoint = Get-MIRAssuranceCampaignCheckpoint -Test $Test -Plan $Plan -Context $Context
        if ($null -ne $checkpoint) {
          $checkpoint.disposition = "WAIT"
          $checkpoint.decision_reason = "adopted-exact-plan-owned-fresh-checkpoint"
          return $checkpoint
        }
      }
      Write-Host "[RUN] no exact campaign checkpoint after prior worker; continuing $id"
    }
  }
  $decision = Get-MIRAssuranceEvidenceDecision -Fingerprint $fingerprint -Context $Context -TestId $id
  if ([string]$decision.disposition -eq "REUSE") {
    Write-Host "[REUSE] $id $($fingerprint.input_key)"
    return $decision.evidence
  }
  if ([string]$decision.disposition -eq "WAIT") {
    Write-Host "[WAIT] $id $($fingerprint.input_key)"
    $adopted = Wait-MIRAssuranceEvidence -Fingerprint $fingerprint -Context $Context
    if ($null -ne $adopted) {
      $adopted.disposition = "WAIT"
      $adopted.decision_reason = "adopted-matching-worker-result"
      return $adopted
    }
    Write-Host "[RUN] matching worker expired without reusable evidence; adopting $id"
  } else {
    Write-Host "[$($decision.disposition)] $id $($fingerprint.input_key)"
  }

  $evidenceProducer = Get-MIRAssuranceEvidenceProducer -Test $Test -Plan $Plan -Context $Context
  $null = Write-MIRAssuranceRunningEvidence -Fingerprint $fingerprint -Context $Context -Plan $Plan -Test $Test
  $started = Get-Date
  $status = "failed"
  $message = ""
  $resolvedCommand = ""
  $exitCode = 1
  $assertions = @()
  $artifacts = @()
  $paths = Get-MIRAssuranceEvidencePaths -TestId $id -InputKey ([string]$fingerprint.input_key)
  $workRoot = Join-Path $paths.root (Join-Path "work" ([guid]::NewGuid().ToString("N")))
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  $stdoutPath = Join-Path $workRoot "stdout.txt"
  $stderrPath = Join-Path $workRoot "stderr.txt"
  $resultPath = Join-Path $workRoot "result.json"
  $performanceOutputPath = Join-Path $workRoot "performance-regression.json"
  [IO.File]::WriteAllText($stdoutPath, "", [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($stderrPath, "", [Text.UTF8Encoding]::new($false))
  try {
    $commandResult = Invoke-MIRAssuranceCommandText `
      -Command ([string]$Test.command) `
      -Context $Context `
      -Plan $Plan `
      -StdoutPath $stdoutPath `
      -StderrPath $stderrPath `
      -TestOutput $performanceOutputPath
    $resolvedCommand = [string]$commandResult.resolved_command
    $exitCode = [int]$commandResult.exit_code
    if ($exitCode -ne 0) {
      throw "Command exited with code $exitCode."
    }
    if ([string]$Test.kind -eq "factorio-scenario") {
      $scenarioSummaryPath = Join-Path $repo "build\results\validation\$([string]$Test.safe_test_id).json"
      $capturedScenarioSummaryPath = Join-Path $workRoot "scenario-summary.json"
      Copy-Item -LiteralPath $scenarioSummaryPath -Destination $capturedScenarioSummaryPath -Force
      $scenarioResult = Get-MIRAssuranceScenarioResult -Test $Test -SummaryPath $capturedScenarioSummaryPath
      $assertions = @($scenarioResult.assertions)
      $artifacts = @($scenarioResult.artifacts)
    } elseif ($id -eq "runtime.performance-regression") {
      $performanceEvidence = Test-MIRRuntimePerformanceEvidence `
        -RepoRoot $repo `
        -Path $performanceOutputPath `
        -Candidate $Context.candidate `
        -PriorRelease $Context.prior_release `
        -FactorioBin $Context.factorio `
        -ExpectedSourceCommit ([string]$Plan.source_commit) `
        -ExpectedBaselineVersion ([string]$Context.verification_profile.upgrade.from_version) `
        -ExpectedFactorioVersion ([string]$Context.verification_profile.qualification_factorio_version) `
        -CampaignPath (Resolve-MIRAssurancePerformanceCampaignPath -Context $Context)
      $performanceDescriptor = Get-MIRAssuranceArtifactDescriptor -Path $performanceEvidence.path -Kind "runtime-performance-evidence"
      $assertions = @(
        [ordered]@{
          id="runtime-performance-evidence-validated"
          status="passed"
          evidence=[string]$performanceDescriptor.path
        }
      )
      $artifacts = @($performanceDescriptor)
    } else {
      $assertions = @(
        [ordered]@{
          id="executor-exit-zero"
          status="passed"
          evidence=(Get-MIRAssuranceRepoRelativePath -Path $stdoutPath)
        }
      )
    }
    $status = "passed"
  } catch {
    $status = "failed"
    $message = $_.Exception.Message
    if ($exitCode -eq 0) { $exitCode = 1 }
    $assertions = @(
      [ordered]@{
        id="executor-exit-zero"
        status="failed"
        evidence=(Get-MIRAssuranceRepoRelativePath -Path $stderrPath)
      }
    )
  }
  $completed = Get-Date
  $duration = [Math]::Round(($completed - $started).TotalSeconds, 3)
  $structuredResult = [ordered]@{
    schema="mir-test-result-v1"
    test_id=$id
    status=$status
    exit_code=$exitCode
    assertions=@($assertions)
    artifacts=@($artifacts)
    started_at=$started.ToUniversalTime().ToString("o")
    completed_at=$completed.ToUniversalTime().ToString("o")
    message=$message
  }
  Write-MIRAssuranceAtomicJson -Value $structuredResult -Path $resultPath
  $resultDescriptor = Get-MIRAssuranceArtifactDescriptor -Path $resultPath -Kind "structured-test-result"
  $resultDescriptor["schema"] = "mir-test-result-v1"
  $resultDescriptor["status"] = $status
  $capsule = [ordered]@{
    schema=$evidenceSchema
    test_id=$id
    status=$status
    conclusion=$status
    disposition="RUN"
    input_key=[string]$fingerprint.input_key
    fingerprint_sha256=[string]$fingerprint.fingerprint_sha256
    definition_sha256=[string]$fingerprint.definition_sha256
    target=[string]$Context.target
    layer=[string]$Test.layer
    command=[string]$Test.command
    resolved_command=$resolvedCommand
    inputs=$fingerprint.inputs
    producer=$evidenceProducer
    assertions=$assertions
    exit_code=$exitCode
    result=$resultDescriptor
    artifacts=@($artifacts)
    stdout_sha256=(Get-MIRAssuranceSha256 -Path $stdoutPath)
    stderr_sha256=(Get-MIRAssuranceSha256 -Path $stderrPath)
    log_digest=(Get-MIRAssuranceTextHash -Text ((Get-Content -Raw -LiteralPath $stdoutPath) + "`n" + (Get-Content -Raw -LiteralPath $stderrPath)))
    started_at=$started.ToUniversalTime().ToString("o")
    completed_at=$completed.ToUniversalTime().ToString("o")
    duration_seconds=$duration
    message=$message
  }
  $capsule = Write-MIRAssuranceAttempt -Capsule $capsule
  if ($status -ne "passed") { throw "Assurance test failed: $id - $message" }
  return $capsule
}

function Invoke-MIRAssurancePlan {
  param(
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context,
    [int]$TimeBudgetSeconds = -1,
    $ExecutionState = $null
  )
  $results = @()
  $startedAt = [DateTimeOffset]::UtcNow
  $deadline = if ($TimeBudgetSeconds -ge 0) { $startedAt.AddSeconds($TimeBudgetSeconds) } else { $null }
  if ($null -ne $ExecutionState) {
    $ExecutionState["status"] = "complete"
    $ExecutionState["started_at"] = $startedAt.ToString("o")
    $ExecutionState["time_budget_seconds"] = $TimeBudgetSeconds
  }
  foreach ($test in @($Plan.tests)) {
    if ($null -ne $deadline -and [DateTimeOffset]::UtcNow -ge $deadline) {
      if ($null -ne $ExecutionState) {
        $ExecutionState["status"] = "checkpointed"
        $ExecutionState["next_test_id"] = [string]$test.id
        $ExecutionState["completed_at"] = [DateTimeOffset]::UtcNow.ToString("o")
      }
      Write-Host "[CHECKPOINT] Time budget reached before '$([string]$test.id)'; completed rows are durable and the same --plan will resume only the remaining rows."
      break
    }
    try {
      $results += Invoke-MIRAssuranceTest -Test $test -Plan $Plan -Context $Context
    } catch {
      $capturedFailure = $false
      $paths = Get-MIRAssuranceEvidencePaths -TestId ([string]$test.id) -InputKey ([string]$test.fingerprint.input_key)
      if (Test-Path -LiteralPath $paths.blocked -PathType Leaf) {
        $blocked = Read-MIRAssuranceEvidencePointer -Path $paths.blocked
        if ($null -ne $blocked) {
          $results += $blocked
          $capturedFailure = $true
        }
      }
      if (-not $capturedFailure) {
        $results += [pscustomobject][ordered]@{
          schema="mir-plan-execution-error-v1"
          test_id=[string]$test.id
          status="failed"
          conclusion="failed"
          disposition="RUN"
          input_key=[string]$test.fingerprint.input_key
          fingerprint_sha256=[string]$test.fingerprint.fingerprint_sha256
          exit_code=1
          message=$_.Exception.Message
          completed_at=(Get-Date).ToUniversalTime().ToString("o")
        }
      }
      break
    }
  }
  if ($null -ne $ExecutionState -and -not $ExecutionState.Contains("completed_at")) {
    $ExecutionState["completed_at"] = [DateTimeOffset]::UtcNow.ToString("o")
  }
  return @($results)
}

function Invoke-MIRAssuranceGate {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  $Plan = Assert-MIRAssurancePlan -Plan $Plan -Context $Context
  $checks = @()
  $evidence = @()
  if ($Plan.domain_manifest) {
    $currentManifest = Get-MIRAssuranceDomainManifest -Context $Context -RequireCandidate
    if ([string]$currentManifest.manifest_sha256 -ne [string]$Plan.domain_manifest.manifest_sha256) {
      throw "Candidate domain manifest changed after the verification plan was created."
    }
  }
  foreach ($test in @($Plan.tests)) {
    $fingerprint = $test.fingerprint
    $capsule = Get-MIRAssuranceReusableEvidence -Fingerprint $fingerprint -Context $Context
    $passed = $null -ne $capsule
    if ($passed -and [bool]$test.force_fresh) {
      if (-not (Test-MIRAssuranceFreshCampaignEvidence -Capsule $capsule -Test $test -Plan $Plan)) { $passed = $false }
    }
    $checks += [ordered]@{
      test_id=[string]$test.id
      fingerprint=[string]$fingerprint.fingerprint_sha256
      status=if ($passed) { "passed" } else { "missing-or-invalid" }
    }
    if ($passed) { $evidence += $capsule }
  }
  $failed = @($checks | Where-Object status -ne "passed")
  $evidenceIds = @($evidence | ForEach-Object { [string]$_.test_id } | Sort-Object)
  $evidenceSetMatches = @(Compare-Object @($Plan.expected_test_ids | Sort-Object) $evidenceIds).Count -eq 0
  $capsuleDigests = @(
    foreach ($capsule in @($evidence | Sort-Object test_id)) {
      [ordered]@{
        test_id=[string]$capsule.test_id
        input_key=[string]$capsule.input_key
        result_digest=[string]$capsule.result_digest
      }
    }
  )
  $bundle = [ordered]@{
    schema=2
    policy_id=[string]$Plan.policy_id
    status=if ($failed.Count -eq 0) { "passed" } else { "failed" }
    target=[string]$Plan.target
    plan_generated_at=[string]$Plan.generated_at
    plan_sha256=(Get-MIRAssuranceJsonHash -Value $Plan)
    plan_material_sha256=[string]$Plan.plan_material_sha256
    required_test_set_sha256=[string]$Plan.required_test_set_sha256
    candidate_descriptor=$Plan.candidate_descriptor
    candidate_descriptor_sha256=[string]$Plan.candidate_descriptor_sha256
    candidate=[string]$Plan.candidate
    domain_manifest=$Plan.domain_manifest
    checks=$checks
    evidence=$evidence
    capsule_set=$capsuleDigests
    capsule_set_sha256=(Get-MIRAssuranceJsonHash -Value $capsuleDigests)
    completed_at=(Get-Date).ToUniversalTime().ToString("o")
  }
  $bundle["bundle_sha256"] = Get-MIRAssuranceJsonHash -Value $bundle
  $bundlePath = "build/results/assurance/evidence-bundle.json"
  Write-MIRAssuranceJsonFile -Value $bundle -Path $bundlePath | Out-Null
  $requestedOutput = Get-MIRAssuranceOption -Name "--output"
  if ($requestedOutput -and (Resolve-MIRAssurancePath -Path $requestedOutput) -ne (Resolve-MIRAssurancePath -Path $bundlePath)) {
    Write-MIRAssuranceJsonFile -Value $bundle -Path $requestedOutput | Out-Null
  }
  if (Test-MIRAssuranceSwitch -Name "--json") {
    $bundle | ConvertTo-Json -Depth 40 | Write-Output
  }
  if ($failed.Count -gt 0) {
    throw "MIR verification gate is missing trusted exact evidence for $($failed.Count) test(s): $(@($failed.test_id) -join ', ')"
  }
  if (-not $evidenceSetMatches) {
    throw "Evidence bundle test set differs from the canonical verification plan."
  }
  return $bundle
}

function Get-MIRAssuranceBuildFingerprint {
  param([Parameter(Mandatory)]$Context)
  $material = [ordered]@{
    schema=$buildReceiptSchema
    target=[string]$Context.target
    source_tree=(& git -C $repo rev-parse "HEAD^{tree}").Trim()
    package_source_sha256=(Get-MIRAssurancePackageSourceHash)
    build_script_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "tools\commands\package\Build-MIRPackage.ps1"))
    package_identity_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "tools\lib\validation\PackageIdentity.ps1"))
    info_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "info.json"))
  }
  return [ordered]@{ material=$material; input_key=(Get-MIRAssuranceJsonHash -Value $material) }
}

function Test-MIRAssuranceBuildReceipt {
  param([Parameter(Mandatory)]$Fingerprint, [Parameter(Mandatory)]$Context)
  $path = Join-Path $buildRoot "$($Fingerprint.input_key).json"
  if (-not $Context.reuse_enabled -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) { return $null }
  try { $receipt = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json }
  catch { return $null }
  if ([int]$receipt.schema -ne $buildReceiptSchema) { return $null }
  if ([string]$receipt.input_key -ne [string]$Fingerprint.input_key) { return $null }
  if ([string]$receipt.candidate_sha256 -ne (Get-MIRAssuranceSha256 -Path $Context.candidate)) { return $null }
  if ([string]$receipt.candidate_content_sha256 -ne (Get-MIRAssuranceZipContentHash -Path $Context.candidate)) { return $null }
  $result = ConvertTo-MIRAssuranceOrderedMap -Object $receipt
  $result.disposition = "reused"
  $result.receipt = Get-MIRAssuranceRepoRelativePath -Path $path
  return $result
}

function Invoke-MIRAssuranceBuild {
  param([Parameter(Mandatory)]$Context)
  New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
  $fingerprint = Get-MIRAssuranceBuildFingerprint -Context $Context
  $reused = Test-MIRAssuranceBuildReceipt -Fingerprint $fingerprint -Context $Context
  if ($null -ne $reused) {
    Write-Host "[reuse] candidate build $($fingerprint.input_key)"
    return $reused
  }
  Write-Host "[run] candidate build $($fingerprint.input_key)"
  $candidateFullPath = [IO.Path]::GetFullPath([string]$Context.candidate)
  $distRoot = [IO.Path]::GetFullPath((Join-Path $repo "dist"))
  if ($candidateFullPath.StartsWith($distRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Assurance builds may not write through immutable published dist authority: $candidateFullPath"
  }
  $canonicalAssuranceRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build\packages\assurance'))
  $isMir4CanonicalBuild = $candidateFullPath.StartsWith(
    $canonicalAssuranceRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase
  )
  $recordPath = Join-Path $repo ".mir\releases\records\$($Context.info.version).json"
  if (-not $isMir4CanonicalBuild -and (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
    $record = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json
    if ([string]$record.state -in @("tagged", "published", "publicly-verified")) {
      $observedSource = Get-MIRAssurancePackageSourceHash
      if ($observedSource -ne [string]$record.package.source_sha256) {
        throw "Refusing to build published version $($Context.info.version) from changed package roots: expected $($record.package.source_sha256), observed $observedSource. Restore the governed published source baseline first."
      }
    }
  }
  if ($isMir4CanonicalBuild) {
    . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
    $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
    $targetRows = @($authority.targets | Where-Object { [string]$_.target_id -ceq "factorio-$([string]$Context.target)" })
    if ($targetRows.Count -ne 1) { throw "Assurance target is not governed by canonical MIR 4 package authority: $($Context.target)" }
    $candidateId = 'MIR4-ASSURANCE-' + ([string]$fingerprint.material.source_tree).ToUpperInvariant()
    $sourceVersion = if ([string]$Context.info.version -match '^4[.]') {
      [string]$Context.info.version
    } else {
      [string]$targetRows[0].baseline_source_version
    }
    $buildArguments = @{
      Target = [string]$targetRows[0].target
      CandidateId = $candidateId
      SourceVersion = $sourceVersion
      OutputDir = 'build/packages/assurance'
    }
    $buildResult = & (Join-Path $repo 'tools/commands/package/Build-MIRPackage.ps1') @buildArguments
    if ([IO.Path]::GetFullPath([string]$buildResult.archive_path) -cne $candidateFullPath) {
      throw "Canonical assurance build produced an unexpected archive path: $([string]$buildResult.archive_path)"
    }
  } else {
    throw "Current assurance builds must use canonical MIR 4 package authority below build/packages/assurance: $candidateFullPath"
  }
  if (-not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) { throw "Candidate was not created: $($Context.candidate)" }
  $receipt = [ordered]@{
    schema=$buildReceiptSchema
    status="passed"
    disposition="executed"
    input_key=[string]$fingerprint.input_key
    target=[string]$Context.target
    candidate=(Get-MIRAssuranceRepoRelativePath -Path $Context.candidate)
    candidate_sha256=(Get-MIRAssuranceSha256 -Path $Context.candidate)
    candidate_content_sha256=(Get-MIRAssuranceZipContentHash -Path $Context.candidate)
    package_source_sha256=[string]$fingerprint.material.package_source_sha256
    size_bytes=(Get-Item -LiteralPath $Context.candidate).Length
    completed_at=(Get-Date).ToUniversalTime().ToString("o")
  }
  $path = Join-Path $buildRoot "$($fingerprint.input_key).json"
  [IO.File]::WriteAllText($path, (($receipt | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
  $receipt["receipt"] = Get-MIRAssuranceRepoRelativePath -Path $path
  return $receipt
}

function Get-MIRAssuranceResultCounts {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()]$Results,
    [int]$ExpectedTotal = -1
  )
  $total = @($Results).Count
  $expected = if ($ExpectedTotal -ge 0) { $ExpectedTotal } else { $total }
  return [ordered]@{
    expected=$expected
    total=$total
    executed=@($Results | Where-Object { [string]$_.disposition -eq "RUN" }).Count
    reused=@($Results | Where-Object { [string]$_.disposition -in @("REUSE", "WAIT") }).Count
    checkpointed=@($Results | Where-Object { [string]$_.disposition -eq "CHECKPOINT" }).Count
    failed=@($Results | Where-Object { [string]$_.status -ne "passed" }).Count
    incomplete=[Math]::Max(0, $expected - $total)
    unexpected=[Math]::Max(0, $total - $expected)
  }
}
