function Invoke-MIRAssuranceSelfTest {
  param([Parameter(Mandatory)]$Context)

  $timestampProbeRecord = '{"recorded_at":"2026-08-18T12:00:00+10:00"}' |
    ConvertFrom-Json -DateKind String
  $timestampProbe = ConvertTo-MIR4BootstrapCanonicalJson -Value $timestampProbeRecord
  if ($timestampProbe -cne '{"recorded_at":"2026-08-18T12:00:00+10:00"}') {
    throw 'Bootstrap authority timestamps must remain lexical and time-zone independent.'
  }

  $canonicalTrustPath = Get-MIRAssuranceCanonicalTrustPolicyPath
  $canonicalTrustSha256 = Get-MIRAssuranceCanonicalJsonFileHash -Path $canonicalTrustPath
  $decoyTrustPath = Join-Path $repo "validation\domains.yml"
  if (-not (Test-Path -LiteralPath $decoyTrustPath -PathType Leaf) -or
      (Get-MIRAssuranceCanonicalJsonFileHash -Path $decoyTrustPath) -eq $canonicalTrustSha256) {
    throw "Trust-path collision self-test requires a distinct target-line policy fixture."
  }
  $originalTrustPath = $trustPath
  try {
    $trustPath = $decoyTrustPath
    $collisionProducer = Get-MIRAssuranceProducer
    $collisionContext = Get-MIRAssuranceContext
    if ([string]$collisionProducer.policy_sha256 -ne $canonicalTrustSha256 -or
        (Get-MIRAssuranceJsonHash -Value $collisionContext.trust_policy) -ne
        (Get-MIRAssuranceJsonHash -Value (Get-Content -Raw -LiteralPath $canonicalTrustPath | ConvertFrom-Json))) {
      throw "A dynamically scoped trustPath collision changed canonical producer or context authority."
    }
  } finally {
    $trustPath = $originalTrustPath
  }

  $cases = @(
    @{path="control.lua"; class="runtime-or-migration"},
    @{path="migrations/more-infinite-research_3.1.9.json"; class="runtime-or-migration"},
    @{path="settings.lua"; class="settings"},
    @{path="locale/en/more-infinite-research.cfg"; class="locale"},
    @{path="docs/maintainer/example.md"; class="repository-docs"},
    @{path="scripts/Invoke-MIRValidation.ps1"; class="test-harness"},
    @{path="unclassified.future"; class="unknown"}
  )
  foreach ($case in $cases) {
    $actual = Get-MIRAssuranceClassification -Paths @($case.path) -Config $Context.config
    if ($actual.classes -notcontains $case.class) { throw "Classifier self-test failed for $($case.path)." }
  }

  $fixtureFingerprint = Get-MIRAssuranceScenarioFixtureFingerprint -Test ([pscustomobject]@{
    id = "scenario/2.1/compiler-contracts"
    scenario = [pscustomobject]@{
      group = "local-mod-library"
      fixtures = @("mir-fixture-assert-compiler-contracts")
    }
  })
  if (@($fixtureFingerprint.patterns) -notcontains "fixtures/assert-compiler-contracts/**") {
    throw "Scenario fixture fingerprint did not resolve the fixture mod ID to its repository directory."
  }
  if (@($fixtureFingerprint.patterns) -contains "fixtures/mir-fixture-assert-compiler-contracts/**") {
    throw "Scenario fixture fingerprint incorrectly treated a fixture mod ID as a repository directory."
  }
  if ([int]$fixtureFingerprint.file_count -lt 3) {
    throw "Scenario fixture fingerprint did not capture the compiler-contract fixture source files."
  }
  $unknownFixtureRejected = $false
  try {
    $null = Get-MIRAssuranceFixturePathByModId -ModId "mir-fixture-does-not-exist"
  } catch {
    $unknownFixtureRejected = $true
  }
  if (-not $unknownFixtureRejected) {
    throw "Unknown scenario fixture mod ID was accepted by the evidence fingerprint resolver."
  }

  $baseMaterial = [ordered]@{test="a"; candidate="a"; binary="a"; harness="a"; settings="a"}
  $base = Get-MIRAssuranceJsonHash -Value $baseMaterial
  foreach ($field in @("candidate", "binary", "harness", "settings")) {
    $changed = [ordered]@{test="a"; candidate="a"; binary="a"; harness="a"; settings="a"}
    $changed[$field] = "b"
    if ((Get-MIRAssuranceJsonHash -Value $changed) -eq $base) { throw "Evidence invalidation self-test failed for $field." }
  }
  $activeApprovedDeltaProfile = $Context.verification_profile
  $activeApprovedDeltaPath = Resolve-MIRAssuranceApprovedDeltaPath -VerificationProfile $activeApprovedDeltaProfile
  $activeApprovedDeltaFrom = [string]$activeApprovedDeltaProfile.upgrade.from_version
  $activeApprovedDeltaTo = [string]$activeApprovedDeltaProfile.upgrade.to_version
  $expectedApprovedDeltaPath = Resolve-MIRAssuranceRepoPathId -Id "releases.deltas" -Suffix "$activeApprovedDeltaFrom-to-$activeApprovedDeltaTo.json"
  if ($activeApprovedDeltaPath -ne $expectedApprovedDeltaPath) {
    throw "Approved-delta transition resolver did not select the active release-transition artifact."
  }
  $activeApprovedDeltaFingerprint = Get-MIRAssuranceApprovedDeltaTransitionFingerprint -Context $Context
  if ([string]$activeApprovedDeltaFingerprint.path -ne $activeApprovedDeltaPath -or
      [string]$activeApprovedDeltaFingerprint.sha256 -notmatch '^[A-F0-9]{64}$' -or
      [string]$activeApprovedDeltaFingerprint.state -notin @("pending", "present")) {
    throw "Active approved-delta transition fingerprint is invalid: $activeApprovedDeltaPath"
  }
  if ([string]$activeApprovedDeltaFingerprint.state -eq "pending") {
    $developmentContext = [string]$activeApprovedDeltaFingerprint.authority_class -ceq 'development-context-no-release-authority'
    $validBoundary = if ($developmentContext) {
      [string]$activeApprovedDeltaFingerprint.release_state -ceq 'active-private-mir4.1-qualification-no-release-authority'
    } else {
      [string]$activeApprovedDeltaFingerprint.release_state -in @("planned", "source-frozen", "package-built", "authorized-in-progress")
    }
    if (-not $validBoundary -or [string]$activeApprovedDeltaFingerprint.release_record_sha256 -notmatch '^[A-F0-9]{64}$') {
      throw "Pending approved-delta transition does not bind its exact pre-qualification authority or no-release development context."
    }
  }
  $alternateApprovedDeltaPath = Resolve-MIRAssuranceApprovedDeltaPath -VerificationProfile ([pscustomobject]@{
    upgrade=[pscustomobject]@{from_version="9.9.9"; to_version="9.9.10"}
  })
  if ($alternateApprovedDeltaPath -eq $activeApprovedDeltaPath) {
    throw "Approved-delta transition change did not invalidate the resolved input path."
  }
  $unsafeApprovedDeltaRejected = $false
  try {
    $null = Resolve-MIRAssuranceApprovedDeltaPath -VerificationProfile ([pscustomobject]@{
      upgrade=[pscustomobject]@{from_version="../9.9.9"; to_version="9.9.10"}
    })
  } catch {
    $unsafeApprovedDeltaRejected = $true
  }
  if (-not $unsafeApprovedDeltaRejected) {
    throw "Approved-delta transition resolver accepted an unsafe version value."
  }

  $manualC21Path = Resolve-MIRAssuranceManualReviewAttestationPath -Info ([pscustomobject]@{version="3.2.1"})
  $manualC24Path = Resolve-MIRAssuranceManualReviewAttestationPath -Info ([pscustomobject]@{version="3.2.2"})
  if ($manualC21Path -ne ".mir/evidence/3.2.1-manual-review-attestation.json" -or
      $manualC24Path -ne ".mir/evidence/3.2.2-manual-review-attestation.json") {
    throw "Manual-review resolver did not select the exact versioned attestation."
  }
  $unsafeManualReviewRejected = $false
  try {
    $null = Resolve-MIRAssuranceManualReviewAttestationPath -Info ([pscustomobject]@{version="../3.2.2"})
  } catch {
    $unsafeManualReviewRejected = $true
  }
  if (-not $unsafeManualReviewRejected) {
    throw "Manual-review resolver accepted an unsafe version value."
  }

  $dependencyA = Get-MIRAssuranceDependencyContract -Info ([pscustomobject]@{
    name="more-infinite-research"; version="3.1.9"; factorio_version="2.1"; dependencies=@("base >= 2.1.8")
  })
  $dependencyB = Get-MIRAssuranceDependencyContract -Info ([pscustomobject]@{
    name="more-infinite-research"; version="3.2.0"; factorio_version="2.1"; dependencies=@("base >= 2.1.8")
  })
  if ((Get-MIRAssuranceJsonHash -Value $dependencyA) -ne (Get-MIRAssuranceJsonHash -Value $dependencyB)) {
    throw "Version-only metadata unexpectedly invalidated the dependency contract."
  }

  foreach ($candidateId in @("C1", "C21", "2.5-P1", "2.5-P99", "10.12-P3")) {
    if (-not (Test-MIRAssuranceReleaseCandidateId -CandidateId $candidateId)) {
      throw "Valid release candidate ID was rejected: $candidateId"
    }
  }
  foreach ($candidateId in @("C0", "C01", "C-1", "2.5-P0", "2.5-P01", "2-P1", "2.5-C1", "candidate")) {
    if (Test-MIRAssuranceReleaseCandidateId -CandidateId $candidateId) {
      throw "Invalid release candidate ID was accepted: $candidateId"
    }
  }

  $planningAuthority = Get-MIRAssuranceReleasePlanningAuthority -Context $Context
  if ([string]$planningAuthority.state -eq "planned") {
    if ([string]$planningAuthority.authority_class -ne "planned-reservation" -or
        [string]$planningAuthority.candidate_id -ne "not-assigned" -or
        [string]$planningAuthority.package_source_commit -ne (Resolve-MIRAssuranceCommit -Commit HEAD)) {
      throw "Planned release reservation did not produce a source-bound non-candidate planning authority."
    }
    $candidateAuthorityRejected = $false
    try {
      $null = Get-MIRAssuranceReleaseCandidateAuthority -Context $Context
    } catch {
      $candidateAuthorityRejected = $true
    }
    if (-not $candidateAuthorityRejected) {
      throw "Planned release reservation was incorrectly accepted as exact candidate authority."
    }
  }

  if ([string]$Context.target -eq "2.1" -and [string]$Context.info.version -eq "3.2.0") {
    $authority = Get-MIRAssuranceReleaseCandidateAuthority -Context $Context
    $qualificationCommit = Resolve-MIRAssuranceCommit -Commit HEAD
    $packageMaterial = Get-MIRAssurancePackageAuthorityHash `
      -PackageSourceCommit ([string]$authority.package_source_commit) `
      -ContentCommit ([string]$authority.package_source_commit) `
      -Material $authority.package_source_material
    $qualificationMaterial = Get-MIRAssurancePackageAuthorityHash `
      -PackageSourceCommit ([string]$authority.package_source_commit) `
      -ContentCommit $qualificationCommit `
      -Material $authority.package_source_material
    $expectedPackageFileCount = [int]$authority.package_source_material.file_count
    if (-not (Test-MIRAssuranceReleaseCandidateId -CandidateId ([string]$authority.candidate_id)) -or
        [string]$packageMaterial.sha256 -ne [string]$authority.package_source_sha256 -or
        [string]$qualificationMaterial.sha256 -ne [string]$authority.package_source_sha256 -or
        [int]$packageMaterial.file_count -ne $expectedPackageFileCount -or
        [int]$qualificationMaterial.file_count -ne $expectedPackageFileCount -or
        -not (Test-MIRAssurancePackageRootsEqual -ReferenceCommit ([string]$authority.package_source_commit) -DifferenceCommit $qualificationCommit)) {
      throw "Current package-source and qualification-source authority self-test failed."
    }
    $candidateIdentity = Get-MIRAssuranceCandidateArchiveIdentity -Path $Context.candidate
    if ([long]$candidateIdentity.bytes -ne [long]$authority.archive_bytes -or
        [int]$candidateIdentity.entries -ne [int]$authority.archive_entries -or
        [string]$candidateIdentity.sha256 -ne [string]$authority.archive_sha256 -or
        [string]$candidateIdentity.content_sha256 -ne [string]$authority.package_content_sha256 -or
        (Get-MIRAssurancePackageSourceHash) -ne [string]$authority.package_source_sha256) {
      throw "Current candidate, normalized content, and package-source identities do not match release authority."
    }
    $tamperedMaterial = ($authority.package_source_material | ConvertTo-Json -Depth 20) | ConvertFrom-Json
    if ([string]$tamperedMaterial.hash_algorithm -eq "git-commit-normalized-package-v1") {
      $tamperedMaterial.source_tree = "0" * 40
    } else {
      $tamperedMaterial.changed_files[0].captured_worktree_sha256 = "0" * 64
    }
    $tamperedRejected = $false
    try {
      $null = Get-MIRAssurancePackageAuthorityHash `
        -PackageSourceCommit ([string]$authority.package_source_commit) `
        -ContentCommit $qualificationCommit `
        -Material $tamperedMaterial
    } catch { $tamperedRejected = $true }
    if (-not $tamperedRejected) {
      throw "Tampered package-source material was not rejected."
    }
  }

  $selfTestId = "self-test.synthetic"
  $selfTestKey = Get-MIRAssuranceTextHash -Text ([guid]::NewGuid().ToString("N"))
  $fingerprint = [ordered]@{
    schema=$evidenceSchema
    test_id=$selfTestId
    target=[string]$Context.target
    input_key=$selfTestKey
    fingerprint_sha256=$selfTestKey
    definition_sha256=(Get-MIRAssuranceTextHash -Text "definition")
    inputs=[ordered]@{}
  }
  $missingInputFingerprint = [ordered]@{
    schema=$evidenceSchema
    test_id="self-test.required-input"
    target=[string]$Context.target
    input_key=(Get-MIRAssuranceTextHash -Text "missing-required-input")
    fingerprint_sha256=(Get-MIRAssuranceTextHash -Text "missing-required-input")
    definition_sha256=(Get-MIRAssuranceTextHash -Text "missing-required-input-definition")
    inputs=[ordered]@{
      "prior-release"=[ordered]@{kind="external-file"; state="missing"; sha256=(Get-MIRAssuranceTextHash -Text "MISSING:prior-release")}
    }
  }
  $missingInputDecision = Get-MIRAssuranceEvidenceDecision `
    -Fingerprint $missingInputFingerprint -Context $Context -TestId ([string]$missingInputFingerprint.test_id)
  if ([string]$missingInputDecision.disposition -ne "INVALID" -or
      [string]$missingInputDecision.reason -ne "required-input-missing:prior-release") {
    throw "Missing required external input did not invalidate the plan row before execution."
  }
  $paths = Get-MIRAssuranceEvidencePaths -TestId $selfTestId -InputKey $selfTestKey
  $selfTestArtifactRoot = Join-Path $paths.root "work\synthetic"
  New-Item -ItemType Directory -Force -Path $selfTestArtifactRoot | Out-Null
  $selfTestResultPath = Join-Path $selfTestArtifactRoot "result.json"
  $selfTestStdoutPath = Join-Path $selfTestArtifactRoot "stdout.txt"
  $selfTestStderrPath = Join-Path $selfTestArtifactRoot "stderr.txt"
  [IO.File]::WriteAllText($selfTestStdoutPath, "", [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($selfTestStderrPath, "", [Text.UTF8Encoding]::new($false))
  $selfTestAssertions = @(
    [ordered]@{
      id="synthetic"
      status="passed"
      evidence=(Get-MIRAssuranceRepoRelativePath -Path $selfTestResultPath)
    }
  )
  $selfTestStructuredResult = [ordered]@{
    schema="mir-test-result-v1"
    test_id=$selfTestId
    status="passed"
    exit_code=0
    assertions=$selfTestAssertions
    artifacts=@()
    started_at=(Get-Date).ToUniversalTime().ToString("o")
    completed_at=(Get-Date).ToUniversalTime().ToString("o")
    message=""
  }
  Write-MIRAssuranceAtomicJson -Value $selfTestStructuredResult -Path $selfTestResultPath
  $selfTestResultDescriptor = Get-MIRAssuranceArtifactDescriptor -Path $selfTestResultPath -Kind "structured-test-result"
  $selfTestResultDescriptor["schema"] = "mir-test-result-v1"
  $selfTestResultDescriptor["status"] = "passed"
  $emptyFileHash = Get-MIRAssuranceTextHash -Text ""
  $emptyLogHash = Get-MIRAssuranceTextHash -Text "`n"
  $capsule = [ordered]@{
    schema=$evidenceSchema
    test_id=$selfTestId
    status="passed"
    conclusion="passed"
    disposition="RUN"
    input_key=$selfTestKey
    fingerprint_sha256=$selfTestKey
    definition_sha256=$fingerprint.definition_sha256
    target=[string]$Context.target
    command="synthetic"
    resolved_command="synthetic"
    inputs=[ordered]@{}
    producer=(Get-MIRAssuranceProducer)
    assertions=$selfTestAssertions
    exit_code=0
    result=$selfTestResultDescriptor
    artifacts=@()
    stdout_sha256=$emptyFileHash
    stderr_sha256=$emptyFileHash
    log_digest=$emptyLogHash
    started_at=(Get-Date).ToUniversalTime().ToString("o")
    completed_at=(Get-Date).ToUniversalTime().ToString("o")
    duration_seconds=0
    message=""
  }
  $null = Write-MIRAssuranceAttempt -Capsule $capsule
  if ($null -eq (Get-MIRAssuranceReusableEvidence -Fingerprint $fingerprint -Context $Context)) { throw "Passing exact-input evidence was not reusable." }

  $fanInRoot = Join-Path $artifactRoot ("worker-import-self-test\" + [guid]::NewGuid().ToString("N"))
  $fanInPrefix = "mir-selftest-"
  $fanInTest = [pscustomobject][ordered]@{
    id=$selfTestId
    safe_test_id=$selfTestId
    fingerprint=[pscustomobject]$fingerprint
    force_fresh=$false
  }
  $fanInWork = [pscustomobject][ordered]@{
    test_id=$selfTestId
    safe_test_id=$selfTestId
    fingerprint=$selfTestKey
    disposition="RUN"
    layer="F0"
  }
  $fanInPlan = [pscustomobject][ordered]@{tests=@($fanInTest); work=@($fanInWork)}
  $fanInPlan | Add-Member -NotePropertyName plan_material_sha256 -NotePropertyValue (Get-MIRAssuranceTextHash -Text "self-test-plan-material") -Force
  $fanInPlan | Add-Member -NotePropertyName required_test_set_sha256 -NotePropertyValue (Get-MIRAssuranceJsonHash -Value @($selfTestId)) -Force
  $fanInPlan | Add-Member -NotePropertyName generated_at -NotePropertyValue ([string]$capsule.started_at) -Force
  $fanInPlan | Add-Member -NotePropertyName source_commit -NotePropertyValue ([string]$capsule.producer.commit) -Force
  $fanInPlan | Add-Member -NotePropertyName source_tree -NotePropertyValue ((& git -C $repo rev-parse "HEAD^{tree}").Trim()) -Force
  $fanInPlan | Add-Member -NotePropertyName target -NotePropertyValue ([string]$Context.target) -Force
  $fanInPlan | Add-Member -NotePropertyName profile -NotePropertyValue "self-test" -Force
  $fanInPlan | Add-Member -NotePropertyName producer -NotePropertyValue $capsule.producer -Force
  $exactFanInGeneratedAt = [DateTimeOffset]::Parse(
    "2026-08-04T17:49:32.0321566Z",
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::RoundtripKind
  )
  $fanInTimestampCases = @(
    [pscustomobject][ordered]@{label="datetime-offset";value=$exactFanInGeneratedAt},
    [pscustomobject][ordered]@{label="datetime";value=$exactFanInGeneratedAt.UtcDateTime}
  )
  $copyFanInArtifact = {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string[]]$CreationOrder)
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    foreach ($entry in $CreationOrder) {
      $name = if ($entry -eq "expected") { "$fanInPrefix$selfTestId" } else { "${fanInPrefix}decoy" }
      $destination = Join-Path $Root $name
      New-Item -ItemType Directory -Force -Path $destination | Out-Null
      foreach ($item in @(Get-ChildItem -LiteralPath $paths.root -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force
      }
      if ($entry -eq "decoy") {
        $decoyPointerPath = Join-Path $destination "passed.json"
        $decoyPointer = Get-Content -Raw -LiteralPath $decoyPointerPath | ConvertFrom-Json
        $decoyPointer.input_key = "stale-colliding-pointer"
        Write-MIRAssuranceAtomicJson -Value $decoyPointer -Path $decoyPointerPath
        $decoyReceiptPath = Join-Path $destination "worker-receipts\$([string]$fanInPlan.plan_material_sha256).json"
        $decoyReceipt = Get-Content -Raw -LiteralPath $decoyReceiptPath | ConvertFrom-Json
        $decoyReceipt.plan.material_sha256 = Get-MIRAssuranceTextHash -Text "stale-plan-material"
        Write-MIRAssuranceAtomicJson -Value $decoyReceipt -Path $decoyReceiptPath
      }
    }
  }
  $resetFanInDestination = {
    [IO.File]::WriteAllText($paths.passed, "{}`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($paths.blocked, "{}`n", [Text.UTF8Encoding]::new($false))
  }
  $mixedCleanupRoots = [Collections.Generic.List[string]]::new()
  try {
    $originalCulture = [Threading.Thread]::CurrentThread.CurrentCulture
    $originalUiCulture = [Threading.Thread]::CurrentThread.CurrentUICulture
    try {
      [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo("en-AU")
      [Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]::GetCultureInfo("en-AU")
      foreach ($timestampCase in $fanInTimestampCases) {
        $fanInPlan.generated_at = $timestampCase.value
        $null = Write-MIRAssuranceWorkerReceipt -Plan $fanInPlan -Test $fanInTest -Capsule $capsule
        $timestampReceiptPath = Join-Path $paths.root "worker-receipts\$([string]$fanInPlan.plan_material_sha256).json"
        $timestampReceipt = Get-Content -Raw -LiteralPath $timestampReceiptPath | ConvertFrom-Json
        $expectedTimestamp = ConvertTo-MIRAssuranceDateTimeOffset -Value $fanInPlan.generated_at
        $receiptTimestamp = ConvertTo-MIRAssuranceDateTimeOffset -Value $timestampReceipt.plan.generated_at
        $fractionalTicks = $expectedTimestamp.UtcDateTime.Ticks % [TimeSpan]::TicksPerSecond
        if ($fractionalTicks -eq 0 -or
            $receiptTimestamp.UtcDateTime.Ticks -ne $expectedTimestamp.UtcDateTime.Ticks) {
          throw "Worker receipt lost exact fractional timestamp ticks for $([string]$timestampCase.label)."
        }

        $timestampRoot = Join-Path $fanInRoot ("timestamp-" + [string]$timestampCase.label)
        & $copyFanInArtifact $timestampRoot @("expected")
        & $resetFanInDestination
        $timestampImport = Import-MIRAssuranceWorkerEvidence -Plan $fanInPlan -Context $Context -WorkerRoot $timestampRoot -ArtifactPrefix $fanInPrefix
        if ([string]$timestampImport.status -ne "passed" -or
            @($timestampImport.imported).Count -ne 1 -or
            @($timestampImport.rejected).Count -ne 0) {
          throw "Worker fan-in rejected canonical $([string]$timestampCase.label) plan timestamps."
        }
      }
    } finally {
      [Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
      [Threading.Thread]::CurrentThread.CurrentUICulture = $originalUiCulture
    }

    $forwardRoot = Join-Path $fanInRoot "forward"
    $reverseRoot = Join-Path $fanInRoot "reverse"
    & $copyFanInArtifact $forwardRoot @("decoy", "expected")
    & $copyFanInArtifact $reverseRoot @("expected", "decoy")

    & $resetFanInDestination
    $forwardImport = Import-MIRAssuranceWorkerEvidence -Plan $fanInPlan -Context $Context -WorkerRoot $forwardRoot -ArtifactPrefix $fanInPrefix
    $forwardPointerSha256 = Get-MIRAssuranceSha256 -Path $paths.passed
    $forwardCapsule = Read-MIRAssuranceEvidencePointer -Path $paths.passed
    if ($null -eq $forwardCapsule -or (Test-Path -LiteralPath $paths.blocked -PathType Leaf)) {
      throw "Forward-order worker fan-in did not select the exact passing object: $($forwardImport | ConvertTo-Json -Depth 10 -Compress)"
    }

    & $resetFanInDestination
    $reverseImport = Import-MIRAssuranceWorkerEvidence -Plan $fanInPlan -Context $Context -WorkerRoot $reverseRoot -ArtifactPrefix $fanInPrefix
    $reversePointerSha256 = Get-MIRAssuranceSha256 -Path $paths.passed
    $reverseCapsule = Read-MIRAssuranceEvidencePointer -Path $paths.passed
    if ($null -eq $reverseCapsule -or
        $forwardPointerSha256 -ne $reversePointerSha256 -or
        [string]$forwardCapsule.result_digest -ne [string]$reverseCapsule.result_digest -or
        (Get-MIRAssuranceJsonHash -Value $forwardImport.imported) -ne (Get-MIRAssuranceJsonHash -Value $reverseImport.imported)) {
      throw "Worker fan-in changed when unrelated artifact creation order was reversed."
    }

    $mismatchRoot = Join-Path $fanInRoot "mismatch"
    & $copyFanInArtifact $mismatchRoot @("expected")
    $mismatchPointerPath = Join-Path (Join-Path $mismatchRoot "$fanInPrefix$selfTestId") "passed.json"
    $mismatchPointer = Get-Content -Raw -LiteralPath $mismatchPointerPath | ConvertFrom-Json
    $mismatchPointer.input_key = "mismatched-input"
    Write-MIRAssuranceAtomicJson -Value $mismatchPointer -Path $mismatchPointerPath
    & $resetFanInDestination
    $mismatchImport = Import-MIRAssuranceWorkerEvidence -Plan $fanInPlan -Context $Context -WorkerRoot $mismatchRoot -ArtifactPrefix $fanInPrefix
    if ([string]$mismatchImport.status -ne "passed" -or
        [string]$mismatchImport.imported[0].pointer_status -ne "stale-ignored" -or
        $null -eq (Read-MIRAssuranceEvidencePointer -Path $paths.passed)) {
      throw "Worker fan-in treated a stale supplied pointer as evidence authority."
    }

    $missingPointerRoot = Join-Path $fanInRoot "missing-pointer"
    & $copyFanInArtifact $missingPointerRoot @("expected")
    Remove-Item -LiteralPath (Join-Path (Join-Path $missingPointerRoot "$fanInPrefix$selfTestId") "passed.json") -Force
    & $resetFanInDestination
    $missingPointerImport = Import-MIRAssuranceWorkerEvidence -Plan $fanInPlan -Context $Context -WorkerRoot $missingPointerRoot -ArtifactPrefix $fanInPrefix
    if ([string]$missingPointerImport.status -ne "passed" -or
        [string]$missingPointerImport.imported[0].pointer_status -ne "missing" -or
        $null -eq (Read-MIRAssuranceEvidencePointer -Path $paths.passed)) {
      throw "Worker fan-in required a mutable worker pointer instead of deriving it from immutable receipt objects."
    }

    $adoptedRoot = Join-Path $fanInRoot "adopted-exact-evidence"
    & $copyFanInArtifact $adoptedRoot @("expected")
    $adoptedReceiptPath = Join-Path (Join-Path $adoptedRoot "$fanInPrefix$selfTestId") "worker-receipts\$([string]$fanInPlan.plan_material_sha256).json"
    $adoptedReceipt = Get-Content -Raw -LiteralPath $adoptedReceiptPath | ConvertFrom-Json
    $adoptedReceipt.producer.run_id = "trusted-continuation-run"
    $adoptedReceipt.producer.job = "trusted-continuation-worker"
    $adoptedReceipt.evidence_disposition = "adopted-exact-trusted-capsule"
    Write-MIRAssuranceAtomicJson -Value $adoptedReceipt -Path $adoptedReceiptPath
    & $resetFanInDestination
    $adoptedDestinationReceipt = Join-Path $paths.root "worker-receipts\$([string]$fanInPlan.plan_material_sha256).json"
    if (Test-Path -LiteralPath $adoptedDestinationReceipt -PathType Leaf) {
      Remove-Item -LiteralPath $adoptedDestinationReceipt -Force
    }
    $adoptedImport = Import-MIRAssuranceWorkerEvidence -Plan $fanInPlan -Context $Context -WorkerRoot $adoptedRoot -ArtifactPrefix $fanInPrefix
    if ([string]$adoptedImport.status -ne "passed" -or @($adoptedImport.imported).Count -ne 1) {
      throw "Worker fan-in rejected exact trusted evidence adopted by a later trusted worker."
    }

    $receiptMismatchRoot = Join-Path $fanInRoot "receipt-mismatch"
    & $copyFanInArtifact $receiptMismatchRoot @("expected")
    $receiptMismatchPath = Join-Path (Join-Path $receiptMismatchRoot "$fanInPrefix$selfTestId") "worker-receipts\$([string]$fanInPlan.plan_material_sha256).json"
    $receiptMismatch = Get-Content -Raw -LiteralPath $receiptMismatchPath | ConvertFrom-Json
    $receiptMismatch.plan.material_sha256 = "different-verification-context"
    Write-MIRAssuranceAtomicJson -Value $receiptMismatch -Path $receiptMismatchPath
    $receiptMismatchImport = Import-MIRAssuranceWorkerEvidence -Plan $fanInPlan -Context $Context -WorkerRoot $receiptMismatchRoot -ArtifactPrefix $fanInPrefix
    if ([string]$receiptMismatchImport.status -ne "failed" -or @($receiptMismatchImport.rejected).Count -ne 1) {
      throw "Worker fan-in accepted a receipt from a different verification context."
    }

    $producerMismatchRoot = Join-Path $fanInRoot "producer-mismatch"
    & $copyFanInArtifact $producerMismatchRoot @("expected")
    $producerMismatchPath = Join-Path (Join-Path $producerMismatchRoot "$fanInPrefix$selfTestId") "worker-receipts\$([string]$fanInPlan.plan_material_sha256).json"
    $producerMismatch = Get-Content -Raw -LiteralPath $producerMismatchPath | ConvertFrom-Json
    $producerMismatch.producer.job = "different-worker-job"
    Write-MIRAssuranceAtomicJson -Value $producerMismatch -Path $producerMismatchPath
    $producerMismatchImport = Import-MIRAssuranceWorkerEvidence -Plan $fanInPlan -Context $Context -WorkerRoot $producerMismatchRoot -ArtifactPrefix $fanInPrefix
    if ([string]$producerMismatchImport.status -ne "failed" -or @($producerMismatchImport.rejected).Count -ne 1) {
      throw "Worker fan-in accepted a receipt whose declared evidence disposition contradicted its producer lineage."
    }

    $duplicateRoot = Join-Path $fanInRoot "duplicate"
    & $copyFanInArtifact $duplicateRoot @("expected")
    Copy-Item -LiteralPath (Join-Path $duplicateRoot "$fanInPrefix$selfTestId") `
      -Destination (Join-Path $duplicateRoot "$fanInPrefix$selfTestId-duplicate") -Recurse
    $duplicateImport = Import-MIRAssuranceWorkerEvidence -Plan $fanInPlan -Context $Context -WorkerRoot $duplicateRoot -ArtifactPrefix $fanInPrefix
    if ([string]$duplicateImport.status -ne "failed" -or @($duplicateImport.duplicates).Count -ne 1) {
      throw "Worker fan-in did not reject duplicate contributions for one exact plan row."
    }

    foreach ($unsafeWorkerPath in @(
      "C:\absolute\object.json",
      "/absolute/object.json",
      "../traversal/object.json",
      "safe/..\mixed-traversal.json",
      "safe/object.json:alternate-stream"
    )) {
      $unsafeRejected = $false
      try { $null = Get-MIRAssuranceWorkerCanonicalPath -Path $unsafeWorkerPath } catch { $unsafeRejected = $true }
      if (-not $unsafeRejected) { throw "Worker path confinement accepted unsafe syntax: $unsafeWorkerPath" }
    }
    $caseA = Get-MIRAssuranceWorkerCanonicalPath -Path "Case/Object.json"
    $caseB = Get-MIRAssuranceWorkerCanonicalPath -Path "case/object.json"
    $unicodeA = Get-MIRAssuranceWorkerCanonicalPath -Path ("unicode/" + [char]0x00E9 + ".json")
    $unicodeB = Get-MIRAssuranceWorkerCanonicalPath -Path ("unicode/e" + [char]0x0301 + ".json")
    if ([string]$caseA.key -ne [string]$caseB.key -or [string]$unicodeA.key -ne [string]$unicodeB.key) {
      throw "Worker path confinement did not canonicalize case-fold and Unicode-normalization collisions."
    }

    $unicodeCollisionRoot = Join-Path $fanInRoot "unicode-collision"
    New-Item -ItemType Directory -Force -Path $unicodeCollisionRoot | Out-Null
    [IO.File]::WriteAllText((Join-Path $unicodeCollisionRoot (([char]0x00E9) + ".json")), "composed", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $unicodeCollisionRoot ("e" + [char]0x0301 + ".json")), "decomposed", [Text.UTF8Encoding]::new($false))
    $unicodeCollisionRejected = $false
    try { $null = Assert-MIRAssuranceWorkerArtifactTree -ArtifactRoot $unicodeCollisionRoot -Context $Context } catch { $unicodeCollisionRejected = $true }
    if (-not $unicodeCollisionRejected) { throw "Worker artifact ingestion did not reject a Unicode-normalization path collision." }

    if ($env:OS -eq "Windows_NT") {
      $streamRoot = Join-Path $fanInRoot "alternate-stream"
      New-Item -ItemType Directory -Force -Path $streamRoot | Out-Null
      $streamFile = Join-Path $streamRoot "object.json"
      [IO.File]::WriteAllText($streamFile, "primary", [Text.UTF8Encoding]::new($false))
      [IO.File]::WriteAllText("${streamFile}:worker-metadata", "hidden", [Text.UTF8Encoding]::new($false))
      $streamRejected = $false
      try { $null = Assert-MIRAssuranceWorkerArtifactTree -ArtifactRoot $streamRoot -Context $Context } catch { $streamRejected = $true }
      if (-not $streamRejected) { throw "Worker artifact ingestion did not reject an NTFS alternate data stream." }
    }

    $limitRoot = Join-Path $fanInRoot "limit"
    New-Item -ItemType Directory -Force -Path $limitRoot | Out-Null
    [IO.File]::WriteAllText((Join-Path $limitRoot "oversized.txt"), "oversized", [Text.UTF8Encoding]::new($false))
    $limitContext = $Context.PSObject.Copy()
    $limitContext.config = (($Context.config | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
    $limitContext.config.worker_import.max_file_bytes = 1
    $limitRejected = $false
    try { $null = Assert-MIRAssuranceWorkerArtifactTree -ArtifactRoot $limitRoot -Context $limitContext } catch { $limitRejected = $true }
    if (-not $limitRejected) { throw "Worker artifact ingestion did not enforce the individual-file size limit." }

    $mixedPrefix = "mir-mixed-"
    $mixedIds = [ordered]@{
      reuse=$selfTestId
      success="self-test.mixed.success"
      missing="self-test.mixed.missing"
      failed="self-test.mixed.failed"
    }
    $mixedTests = [Collections.Generic.List[object]]::new()
    $mixedWork = [Collections.Generic.List[object]]::new()
    $mixedTests.Add($fanInTest)
    foreach ($role in @("success", "missing", "failed")) {
      $id = [string]$mixedIds[$role]
      $key = Get-MIRAssuranceTextHash -Text "$id-$([guid]::NewGuid().ToString('N'))"
      $test = [pscustomobject][ordered]@{
        id=$id
        safe_test_id=$id
        fingerprint=[pscustomobject][ordered]@{
          schema=$evidenceSchema
          test_id=$id
          target=[string]$Context.target
          input_key=$key
          fingerprint_sha256=$key
          definition_sha256=(Get-MIRAssuranceTextHash -Text "definition-$role")
        }
        force_fresh=$false
      }
      $mixedTests.Add($test)
      $mixedWork.Add([pscustomobject][ordered]@{test_id=$id;safe_test_id=$id;fingerprint=$key;disposition="RUN";layer="F0"})
    }
    $mixedPlan = [pscustomobject][ordered]@{
      tests=@($mixedTests)
      work=@($mixedWork)
      plan_material_sha256=(Get-MIRAssuranceTextHash -Text "mixed-plan-$([guid]::NewGuid().ToString('N'))")
      required_test_set_sha256=(Get-MIRAssuranceJsonHash -Value @($mixedTests.id | Sort-Object))
      generated_at=[string]$capsule.started_at
      source_commit=[string]$capsule.producer.commit
      source_tree=(((& git -C $repo rev-parse "HEAD^{tree}").Trim()))
      target=[string]$Context.target
      profile="self-test-mixed"
      producer=$capsule.producer
    }
    $newMixedContribution = {
      param([Parameter(Mandatory)]$Test, [Parameter(Mandatory)][ValidateSet("passed", "failed")][string]$Status)
      $mixedPaths = Get-MIRAssuranceEvidencePaths -TestId ([string]$Test.id) -InputKey ([string]$Test.fingerprint.input_key)
      $workRoot = Join-Path $mixedPaths.root "work\synthetic"
      New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
      $stdout = Join-Path $workRoot "stdout.txt"
      $stderr = Join-Path $workRoot "stderr.txt"
      $result = Join-Path $workRoot "result.json"
      [IO.File]::WriteAllText($stdout, "", [Text.UTF8Encoding]::new($false))
      [IO.File]::WriteAllText($stderr, "", [Text.UTF8Encoding]::new($false))
      $exitCode = if ($Status -eq "passed") { 0 } else { 1 }
      $evidence = if ($Status -eq "passed") { $stdout } else { $stderr }
      $assertions = @([ordered]@{id="executor-exit-zero";status=$Status;evidence=(Get-MIRAssuranceRepoRelativePath -Path $evidence)})
      $structured = [ordered]@{
        schema="mir-test-result-v1";test_id=[string]$Test.id;status=$Status;exit_code=$exitCode
        assertions=$assertions;artifacts=@();started_at=[string]$capsule.started_at;completed_at=[string]$capsule.completed_at
        message=if($Status -eq "passed"){""}else{"synthetic failure"}
      }
      Write-MIRAssuranceAtomicJson -Value $structured -Path $result
      $descriptor = Get-MIRAssuranceArtifactDescriptor -Path $result -Kind "structured-test-result"
      $descriptor["schema"] = "mir-test-result-v1"
      $descriptor["status"] = $Status
      $mixedCapsule = [ordered]@{
        schema=$evidenceSchema;test_id=[string]$Test.id;status=$Status;conclusion=$Status;disposition="RUN"
        input_key=[string]$Test.fingerprint.input_key;fingerprint_sha256=[string]$Test.fingerprint.fingerprint_sha256
        definition_sha256=[string]$Test.fingerprint.definition_sha256;target=[string]$Context.target;layer="F0"
        command="synthetic";resolved_command="synthetic";inputs=[ordered]@{};producer=$capsule.producer
        assertions=$assertions;exit_code=$exitCode;result=$descriptor;artifacts=@()
        stdout_sha256=(Get-MIRAssuranceSha256 -Path $stdout);stderr_sha256=(Get-MIRAssuranceSha256 -Path $stderr)
        log_digest=(Get-MIRAssuranceTextHash -Text "`n");started_at=[string]$capsule.started_at;completed_at=[string]$capsule.completed_at
        duration_seconds=0;message=if($Status -eq "passed"){""}else{"synthetic failure"}
      }
      $mixedCapsule = Write-MIRAssuranceAttempt -Capsule $mixedCapsule
      $null = Write-MIRAssuranceWorkerReceipt -Plan $mixedPlan -Test $Test -Capsule $mixedCapsule
      return [pscustomobject][ordered]@{paths=$mixedPaths;capsule=$mixedCapsule}
    }
    $mixedSuccess = & $newMixedContribution -Test @($mixedTests | Where-Object id -eq $mixedIds.success)[0] -Status passed
    $mixedFailure = & $newMixedContribution -Test @($mixedTests | Where-Object id -eq $mixedIds.failed)[0] -Status failed
    $mixedCleanupRoots.Add([string]$mixedSuccess.paths.root)
    $mixedCleanupRoots.Add([string]$mixedFailure.paths.root)
    $mixedRoot = Join-Path $fanInRoot "mixed"
    New-Item -ItemType Directory -Force -Path $mixedRoot | Out-Null
    foreach ($contribution in @($mixedSuccess, $mixedFailure)) {
      Copy-Item -LiteralPath $contribution.paths.root -Destination (Join-Path $mixedRoot "$mixedPrefix$([string]$contribution.capsule.test_id)") -Recurse
      Remove-Item -LiteralPath $contribution.paths.root -Recurse -Force
    }
    $irrelevant = Join-Path $mixedRoot "${mixedPrefix}irrelevant"
    Copy-Item -LiteralPath (Join-Path $mixedRoot "$mixedPrefix$($mixedIds.success)") -Destination $irrelevant -Recurse
    $irrelevantReceiptPath = Join-Path $irrelevant "worker-receipts\$([string]$mixedPlan.plan_material_sha256).json"
    $irrelevantReceipt = Get-Content -Raw -LiteralPath $irrelevantReceiptPath | ConvertFrom-Json
    $irrelevantReceipt.plan.material_sha256 = Get-MIRAssuranceTextHash -Text "stale-irrelevant-plan"
    Write-MIRAssuranceAtomicJson -Value $irrelevantReceipt -Path $irrelevantReceiptPath
    $mixedImport = Import-MIRAssuranceWorkerEvidence -Plan $mixedPlan -Context $Context -WorkerRoot $mixedRoot -ArtifactPrefix $mixedPrefix
    $mixedSuccessPaths = Get-MIRAssuranceEvidencePaths -TestId $mixedIds.success -InputKey ([string]@($mixedTests | Where-Object id -eq $mixedIds.success)[0].fingerprint.input_key)
    $mixedFailurePaths = Get-MIRAssuranceEvidencePaths -TestId $mixedIds.failed -InputKey ([string]@($mixedTests | Where-Object id -eq $mixedIds.failed)[0].fingerprint.input_key)
    if ([string]$mixedImport.status -ne "failed" -or @($mixedImport.imported).Count -ne 1 -or
        @($mixedImport.failed).Count -ne 1 -or @($mixedImport.missing).Count -ne 1 -or
        @($mixedImport.ignored).Count -ne 1 -or $null -eq (Read-MIRAssuranceEvidencePointer -Path $paths.passed) -or
        $null -eq (Read-MIRAssuranceEvidencePointer -Path $mixedSuccessPaths.passed) -or
        -not (Test-Path -LiteralPath $mixedFailurePaths.blocked -PathType Leaf)) {
      throw "Mixed REUSE/RUN worker fan-in did not retain reuse, import success, preserve failure, identify missing work, and ignore stale artifacts."
    }
    foreach ($mixedPaths in @($mixedSuccessPaths, $mixedFailurePaths)) {
      if (Test-Path -LiteralPath $mixedPaths.root) { Remove-Item -LiteralPath $mixedPaths.root -Recurse -Force }
    }
  } finally {
    foreach ($mixedRootToRemove in @($mixedCleanupRoots)) {
      if (Test-Path -LiteralPath $mixedRootToRemove) { Remove-Item -LiteralPath $mixedRootToRemove -Recurse -Force }
    }
    if (Test-Path -LiteralPath $fanInRoot) { Remove-Item -LiteralPath $fanInRoot -Recurse -Force }
  }

  $fakeCapsule = ($capsule | ConvertTo-Json -Depth 40) | ConvertFrom-Json
  $fakeCapsule.result = $null
  $fakeCapsule.result_digest = Get-MIRAssuranceCapsuleDigest -Capsule $fakeCapsule
  if ((Test-MIRAssuranceCapsule -Capsule $fakeCapsule -Fingerprint $fingerprint -Context $Context).valid) {
    throw "A fake passing capsule without structured result evidence was accepted."
  }
  $differentTrustClass = if ([string]$Context.trust_class -eq "untrusted-pr") { "protected-integration" } else { "untrusted-pr" }
  $differentTrustCapsule = ($capsule | ConvertTo-Json -Depth 40) | ConvertFrom-Json
  $differentTrustCapsule.producer.trust_class = $differentTrustClass
  $differentTrustCapsule.result_digest = Get-MIRAssuranceCapsuleDigest -Capsule $differentTrustCapsule
  if ((Test-MIRAssuranceCapsule -Capsule $differentTrustCapsule -Fingerprint $fingerprint -Context $Context).valid) {
    throw "Evidence from a different trust class was accepted."
  }
  [IO.File]::WriteAllText($paths.blocked, "{}`n", [Text.UTF8Encoding]::new($false))
  if ($null -ne (Get-MIRAssuranceReusableEvidence -Fingerprint $fingerprint -Context $Context)) { throw "Blocked evidence was incorrectly reusable." }
  $blockedDecision = Get-MIRAssuranceEvidenceDecision -Fingerprint $fingerprint -Context $Context -TestId $selfTestId
  if ($blockedDecision.disposition -ne "INVALID") { throw "Blocked evidence did not invalidate ordinary reuse." }
  $originalRerunTests = @($Context.rerun_tests)
  $originalReuseEnabled = [bool]$Context.reuse_enabled
  try {
    $Context.rerun_tests = @($selfTestId)
    $rerunDecision = Get-MIRAssuranceEvidenceDecision -Fingerprint $fingerprint -Context $Context -TestId $selfTestId
    if ($rerunDecision.disposition -ne "RUN" -or $rerunDecision.reason -ne "explicit-rerun") {
      throw "Explicit rerun did not schedule fresh evidence."
    }
    $Context.rerun_tests = @()
    $Context.reuse_enabled = $false
    $noReuseDecision = Get-MIRAssuranceEvidenceDecision -Fingerprint $fingerprint -Context $Context -TestId $selfTestId
    if ($noReuseDecision.disposition -ne "RUN" -or $noReuseDecision.reason -ne "reuse-disabled") {
      throw "Reuse-disabled planning did not schedule fresh evidence."
    }
  } finally {
    $Context.rerun_tests = $originalRerunTests
    $Context.reuse_enabled = $originalReuseEnabled
  }

  $planPolicyContext = $Context.PSObject.Copy()
  $planPolicyContext.reuse_enabled = $true
  $planPolicyContext.rerun_tests = @()
  Sync-MIRAssuranceContextFromPlan -Context $planPolicyContext -Plan ([pscustomobject][ordered]@{
    reuse_enabled=$false
    rerun_tests=@()
  })
  $planNoReuseDecision = Get-MIRAssuranceEvidenceDecision -Fingerprint $fingerprint -Context $planPolicyContext -TestId $selfTestId
  if ($planPolicyContext.reuse_enabled -or
      $planNoReuseDecision.disposition -ne "RUN" -or
      $planNoReuseDecision.reason -ne "reuse-disabled") {
    throw "A loaded no-reuse plan did not control executor evidence reuse."
  }
  Sync-MIRAssuranceContextFromPlan -Context $planPolicyContext -Plan ([pscustomobject][ordered]@{
    reuse_enabled=$true
    rerun_tests=@($selfTestId)
  })
  $planRerunDecision = Get-MIRAssuranceEvidenceDecision -Fingerprint $fingerprint -Context $planPolicyContext -TestId $selfTestId
  if (-not $planPolicyContext.reuse_enabled -or
      @($planPolicyContext.rerun_tests).Count -ne 1 -or
      $planRerunDecision.disposition -ne "RUN" -or
      $planRerunDecision.reason -ne "explicit-rerun") {
    throw "A loaded explicit-rerun plan did not control executor evidence reuse."
  }

  $freshnessProducer = Get-MIRAssuranceProducer
  $freshnessGeneratedAt = (Get-Date).ToUniversalTime().ToString("o")
  $freshnessPlanMaterial = Get-MIRAssuranceTextHash -Text "freshness-plan-$([guid]::NewGuid().ToString('N'))"
  $freshnessTest = [pscustomobject][ordered]@{
    id="self-test.freshness"
    fingerprint=[pscustomobject]$fingerprint
    force_fresh=$true
    minimum_completed_at=$freshnessGeneratedAt
    required_campaign_id="plan-$($freshnessPlanMaterial.ToLowerInvariant())"
    required_campaign_plan_material_sha256=$freshnessPlanMaterial
  }
  $freshnessPlan = [pscustomobject][ordered]@{
    producer=$freshnessProducer
    source_commit=[string]$freshnessProducer.commit
    generated_at=$freshnessGeneratedAt
    plan_material_sha256=$freshnessPlanMaterial
    campaign=[pscustomobject][ordered]@{
      schema="mir-assurance-campaign-v1"
      id=[string]$freshnessTest.required_campaign_id
      plan_material_sha256=$freshnessPlanMaterial
      created_at=$freshnessGeneratedAt
    }
    reuse_enabled=$false
    rerun_tests=@()
    tests=@($freshnessTest)
  }
  $null = Assert-MIRAssurancePlanFreshnessBinding -Plan $freshnessPlan -Context $Context
  $freshnessTest.required_campaign_id = "plan-$((Get-MIRAssuranceTextHash -Text 'tampered-campaign').ToLowerInvariant())"
  $tamperedFreshnessRejected = $false
  try {
    $null = Assert-MIRAssurancePlanFreshnessBinding -Plan $freshnessPlan -Context $Context
  } catch { $tamperedFreshnessRejected = $true }
  if (-not $tamperedFreshnessRejected) {
    throw "Tampered fresh-evidence campaign binding was accepted."
  }
  if ([string]$Context.trust_class -eq "untrusted-local") {
    $freshnessTest.required_campaign_id = [string]$freshnessPlan.campaign.id
    $boundProducer = Get-MIRAssuranceEvidenceProducer -Test $freshnessTest -Plan $freshnessPlan -Context $Context
    if ([string]$boundProducer.campaign_id -ne [string]$freshnessTest.required_campaign_id -or
        [string]$boundProducer.campaign_plan_material_sha256 -ne [string]$freshnessTest.required_campaign_plan_material_sha256) {
      throw "A local worker did not adopt the plan-owned fresh-evidence identity."
    }
    if ($boundProducer.Contains("Count") -or
        [string]::IsNullOrWhiteSpace([string]$boundProducer.verifier_sha256) -or
        [string]::IsNullOrWhiteSpace([string]$boundProducer.policy_sha256)) {
      throw "A local worker serialized a dictionary wrapper instead of the producer attestation."
    }

    # Regression: an exact row completed before a coordinator timeout is
    # checkpointed by a replacement process; a different plan is rejected.
    $checkpointCapsule = ConvertTo-MIRAssuranceOrderedMap -Object (($capsule | ConvertTo-Json -Depth 40) | ConvertFrom-Json)
    $checkpointCapsule.producer = $boundProducer
    $checkpointCapsule.completed_at = (Get-Date).ToUniversalTime().ToString("o")
    $checkpointCapsule.result_digest = Get-MIRAssuranceCapsuleDigest -Capsule $checkpointCapsule
    $null = Write-MIRAssuranceAttempt -Capsule $checkpointCapsule
    $checkpoint = Get-MIRAssuranceCampaignCheckpoint -Test $freshnessTest -Plan $freshnessPlan -Context $Context
    if ($null -eq $checkpoint -or [string]$checkpoint.disposition -ne "CHECKPOINT") {
      throw "An exact completed campaign row was not checkpointed for a resumed coordinator."
    }
    $wrongCampaignCapsule = ($checkpointCapsule | ConvertTo-Json -Depth 40) | ConvertFrom-Json
    $wrongCampaignCapsule.producer.campaign_id = "plan-$((Get-MIRAssuranceTextHash -Text 'wrong-campaign').ToLowerInvariant())"
    $wrongCampaignCapsule.result_digest = Get-MIRAssuranceCapsuleDigest -Capsule $wrongCampaignCapsule
    if (Test-MIRAssuranceFreshCampaignEvidence -Capsule $wrongCampaignCapsule -Test $freshnessTest -Plan $freshnessPlan) {
      throw "A fresh checkpoint from another plan campaign was accepted."
    }
  }

  $resolvedSelfTestRoot = [IO.Path]::GetFullPath($paths.root)
  $resolvedEvidenceRoot = [IO.Path]::GetFullPath($evidenceRoot).TrimEnd("\") + "\"
  if (-not $resolvedSelfTestRoot.StartsWith($resolvedEvidenceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove assurance self-test evidence outside the evidence root."
  }
  Remove-Item -LiteralPath $resolvedSelfTestRoot -Recurse -Force

  $newRunningCase = {
    param([Parameter(Mandatory)][string]$Label)
    $key = Get-MIRAssuranceTextHash -Text "$Label-$([guid]::NewGuid().ToString('N'))"
    $caseFingerprint = [ordered]@{
      schema=$evidenceSchema
      test_id="self-test.running.$Label"
      target=[string]$Context.target
      input_key=$key
      fingerprint_sha256=$key
      definition_sha256=(Get-MIRAssuranceTextHash -Text "running-definition-$Label")
    }
    $marker = Write-MIRAssuranceRunningEvidence -Fingerprint $caseFingerprint -Context $Context
    return [pscustomobject]@{
      fingerprint=$caseFingerprint
      marker=$marker
      paths=(Get-MIRAssuranceEvidencePaths -TestId $caseFingerprint.test_id -InputKey $caseFingerprint.input_key)
    }
  }
  $writeRunningCase = {
    param([Parameter(Mandatory)]$Case)
    Write-MIRAssuranceAtomicJson -Value $Case.marker -Path $Case.paths.running
  }
  $assertRemovedAndRun = {
    param([Parameter(Mandatory)]$Case, [Parameter(Mandatory)][string]$Message)
    $decision = Get-MIRAssuranceEvidenceDecision -Fingerprint $Case.fingerprint -Context $Context -TestId $Case.fingerprint.test_id
    if ($decision.disposition -ne "RUN" -or (Test-Path -LiteralPath $Case.paths.running -PathType Leaf)) {
      throw $Message
    }
  }

  # 1. A same-host process lease waits while the exact process incarnation is alive.
  $liveProcess = & $newRunningCase "live-process"
  $liveProcess.marker.lease_scope = "process"
  $liveProcess.marker.host_identity = Get-MIRAssuranceHostIdentity
  $liveProcess.marker.process_id = $PID
  $liveProcess.marker.process_started_at = Get-MIRAssuranceProcessStartedAt
  & $writeRunningCase $liveProcess
  $liveDecision = Get-MIRAssuranceEvidenceDecision -Fingerprint $liveProcess.fingerprint -Context $Context -TestId $liveProcess.fingerprint.test_id
  if ($liveDecision.disposition -ne "WAIT") { throw "Same-host live process evidence was not adoptable." }

  # 2. A missing process invalidates its same-host lease.
  $deadProcess = & $newRunningCase "dead-process"
  $deadProcess.marker.lease_scope = "process"
  $deadProcess.marker.host_identity = Get-MIRAssuranceHostIdentity
  $deadProcess.marker.process_id = [int]::MaxValue
  & $writeRunningCase $deadProcess
  & $assertRemovedAndRun $deadProcess "Dead same-host process evidence was incorrectly adoptable."

  # 3. A reused PID cannot adopt a lease created by a different process incarnation.
  $reusedPid = & $newRunningCase "reused-pid"
  $reusedPid.marker.lease_scope = "process"
  $reusedPid.marker.host_identity = Get-MIRAssuranceHostIdentity
  $reusedPid.marker.process_id = $PID
  $reusedPid.marker.process_started_at = [DateTimeOffset]::UtcNow.AddDays(-1).ToString("o")
  & $writeRunningCase $reusedPid
  & $assertRemovedAndRun $reusedPid "A reused PID with a different process start time was incorrectly adoptable."

  # 4. A trusted, unexpired marker from another CI job is adopted without inspecting its remote PID.
  $remoteJob = & $newRunningCase "remote-job"
  $remoteRunId = "remote-$([guid]::NewGuid().ToString('N'))"
  $remoteJob.marker.lease_scope = "ci-job"
  $remoteJob.marker.host_identity = "remote-host-$([guid]::NewGuid().ToString('N'))"
  $remoteJob.marker.process_id = [int]::MaxValue
  $remoteJob.marker.workflow_run_id = $remoteRunId
  $remoteJob.marker.workflow_run_attempt = "1"
  $remoteJob.marker.workflow_job = "remote-worker"
  $remoteJob.marker.producer.run_id = $remoteRunId
  $remoteJob.marker.producer.run_attempt = "1"
  $remoteJob.marker.producer.job = "remote-worker"
  & $writeRunningCase $remoteJob
  $remoteDecision = Get-MIRAssuranceEvidenceDecision -Fingerprint $remoteJob.fingerprint -Context $Context -TestId $remoteJob.fingerprint.test_id
  if ($remoteDecision.disposition -ne "WAIT") { throw "Trusted unexpired remote-job evidence was not adoptable." }

  # 5. An expired remote-job marker is removed and scheduled again.
  $expiredRemote = & $newRunningCase "expired-remote"
  $expiredRunId = "remote-$([guid]::NewGuid().ToString('N'))"
  $expiredRemote.marker.lease_scope = "ci-job"
  $expiredRemote.marker.host_identity = "expired-remote-host"
  $expiredRemote.marker.workflow_run_id = $expiredRunId
  $expiredRemote.marker.workflow_run_attempt = "1"
  $expiredRemote.marker.workflow_job = "expired-worker"
  $expiredRemote.marker.producer.run_id = $expiredRunId
  $expiredRemote.marker.producer.run_attempt = "1"
  $expiredRemote.marker.producer.job = "expired-worker"
  $expiredRemote.marker.expires_at = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString("o")
  & $writeRunningCase $expiredRemote
  & $assertRemovedAndRun $expiredRemote "Expired remote-job evidence was incorrectly adoptable."

  # 6. A marker from another trust class is rejected even when its lease is unexpired.
  $untrustedLease = & $newRunningCase "untrusted-producer"
  $untrustedLease.marker.producer.trust_class = "different-trust-class"
  & $writeRunningCase $untrustedLease
  & $assertRemovedAndRun $untrustedLease "Running evidence from a different trust class was incorrectly adoptable."

  # 7. An explicit rerun bypasses an otherwise valid marker.
  $explicitRerun = & $newRunningCase "explicit-rerun"
  $originalRerunTests = @($Context.rerun_tests)
  try {
    $Context.rerun_tests = @($explicitRerun.fingerprint.test_id)
    $rerunDecision = Get-MIRAssuranceEvidenceDecision -Fingerprint $explicitRerun.fingerprint -Context $Context -TestId $explicitRerun.fingerprint.test_id
    if ($rerunDecision.disposition -ne "RUN" -or $rerunDecision.reason -ne "explicit-rerun") {
      throw "Explicit rerun did not bypass running evidence."
    }
  } finally {
    $Context.rerun_tests = $originalRerunTests
  }

  # 8. Reuse-disabled execution bypasses an otherwise valid marker.
  $reuseDisabled = & $newRunningCase "reuse-disabled"
  $originalReuseEnabled = [bool]$Context.reuse_enabled
  try {
    $Context.reuse_enabled = $false
    $noReuseDecision = Get-MIRAssuranceEvidenceDecision -Fingerprint $reuseDisabled.fingerprint -Context $Context -TestId $reuseDisabled.fingerprint.test_id
    if ($noReuseDecision.disposition -ne "RUN" -or $noReuseDecision.reason -ne "reuse-disabled") {
      throw "Reuse-disabled execution did not bypass running evidence."
    }
  } finally {
    $Context.reuse_enabled = $originalReuseEnabled
  }

  foreach ($runningCase in @(
    $liveProcess,
    $deadProcess,
    $reusedPid,
    $remoteJob,
    $expiredRemote,
    $untrustedLease,
    $explicitRerun,
    $reuseDisabled
  )) {
    if (Test-Path -LiteralPath $runningCase.paths.root) {
      $resolvedRunningRoot = [IO.Path]::GetFullPath($runningCase.paths.root)
      if (-not $resolvedRunningRoot.StartsWith($resolvedEvidenceRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove running self-test evidence outside the evidence root."
      }
      Remove-Item -LiteralPath $resolvedRunningRoot -Recurse -Force
    }
  }

  $emptyPlanRejected = $false
  try {
    $null = Complete-MIRAssurancePlan -Plan ([ordered]@{tests=@()}) -Context $Context
  } catch { $emptyPlanRejected = $true }
  if (-not $emptyPlanRejected) { throw "Empty verification plan was accepted." }

  $completeCounts = Get-MIRAssuranceResultCounts -Results @(
    [pscustomobject]@{status="passed"; disposition="RUN"},
    [pscustomobject]@{status="passed"; disposition="REUSE"}
  ) -ExpectedTotal 2
  if ($completeCounts.failed -ne 0 -or $completeCounts.incomplete -ne 0 -or
      $completeCounts.unexpected -ne 0 -or $completeCounts.total -ne $completeCounts.expected) {
    throw "Complete assurance result cardinality was not accepted."
  }
  $incompleteCounts = Get-MIRAssuranceResultCounts -Results @(
    [pscustomobject]@{status="passed"; disposition="RUN"}
  ) -ExpectedTotal 2
  if ($incompleteCounts.failed -ne 0 -or $incompleteCounts.incomplete -ne 1 -or
      $incompleteCounts.total -eq $incompleteCounts.expected) {
    throw "Incomplete assurance result cardinality was not rejected."
  }
  $preflightFailure = [pscustomobject]@{status="failed"; disposition="RUN"}
  $failedCounts = Get-MIRAssuranceResultCounts -Results @($preflightFailure) -ExpectedTotal 2
  if ($failedCounts.failed -ne 1 -or $failedCounts.incomplete -ne 1) {
    throw "Assurance preflight failure was not retained as failed and incomplete."
  }
  $preflightKey = Get-MIRAssuranceTextHash -Text ("preflight-" + [guid]::NewGuid().ToString("N"))
  $preflightTest = [pscustomobject][ordered]@{
    id="self-test.preflight-failure"
    requires_factorio=$true
    fingerprint=[pscustomobject][ordered]@{
      input_key=$preflightKey
      fingerprint_sha256=$preflightKey
    }
  }
  $preflightPlanResults = @(Invoke-MIRAssurancePlan `
    -Plan ([pscustomobject][ordered]@{tests=@($preflightTest)}) `
    -Context ([pscustomobject][ordered]@{factorio=""}))
  if ($preflightPlanResults.Count -ne 1 -or
      [string]$preflightPlanResults[0].schema -ne "mir-plan-execution-error-v1" -or
      [string]$preflightPlanResults[0].status -ne "failed" -or
      [string]$preflightPlanResults[0].test_id -ne [string]$preflightTest.id -or
      [string]$preflightPlanResults[0].message -notmatch "requires --factorio") {
    throw "Assurance plan execution discarded a preflight failure."
  }
  $checkpointExecution = [ordered]@{}
  $checkpointResults = @(Invoke-MIRAssurancePlan `
    -Plan ([pscustomobject][ordered]@{tests=@($preflightTest)}) `
    -Context ([pscustomobject][ordered]@{factorio=""}) `
    -TimeBudgetSeconds 0 `
    -ExecutionState $checkpointExecution)
  if ([string]$checkpointExecution.status -ne "checkpointed" -or
      [string]$checkpointExecution.next_test_id -ne [string]$preflightTest.id -or
      $checkpointResults.Count -ne 0) {
    throw "A planned time budget did not checkpoint before dispatching the next row."
  }

  $truncatedPlanRejected = $false
  $truncatedPlan = [pscustomobject][ordered]@{
    schema=4
    target=[string]$Context.target
    profile="edit"
    tests=@()
    expected_test_ids=@("static.architecture")
    required_test_set_sha256=(Get-MIRAssuranceJsonHash -Value @("static.architecture"))
    plan_material_sha256="invalid"
  }
  try {
    $null = Assert-MIRAssurancePlan -Plan $truncatedPlan -Context $Context
  } catch { $truncatedPlanRejected = $true }
  if (-not $truncatedPlanRejected) { throw "Truncated verification plan was accepted." }

  $plan = [ordered]@{baseline="abc123"}
  $resolved = Resolve-MIRAssuranceCommandText -Command "./scripts/Invoke-MIRValidation.ps1 -ChangedSince <baseline> -CandidateZip <candidate>" -Context $Context -Plan $plan
  if ($resolved -notmatch "abc123" -or $resolved -match "<baseline>") { throw "Baseline command propagation self-test failed." }

  Write-Host "[ok] MIR assurance classifier, plan closure, structured evidence, lease ownership, trust, freshness binding, blocking, and version-only reuse tests passed."
}
