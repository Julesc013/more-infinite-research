. (Join-Path $PSScriptRoot "Hashing.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "validation\ReleaseAttestations.ps1")

function Invoke-MIRAssuranceSeal {
  param([Parameter(Mandatory)]$Context)
  if (-not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) { throw "Candidate does not exist: $($Context.candidate)" }
  $plan = Get-MIRAssurancePlanFromOption -Context $Context -RequirePlan
  if ([string]$plan.profile -notin @("full", "backport")) {
    throw "Only canonical full or backport verification plans may be sealed."
  }
  $bundle = Invoke-MIRAssuranceGate -Plan $plan -Context $Context
  if ([string]$bundle.status -ne "passed") { throw "Canonical verification gate is not passing." }
  foreach ($capsule in @($bundle.evidence)) {
    if (-not (Test-MIRAssuranceReleaseProducer -Producer $capsule.producer -Context $Context -AllowAncestor)) {
      throw "Release seal rejected evidence from a producer outside the protected-release trust policy: $($capsule.test_id)"
    }
  }
  $producer = Get-MIRAssuranceProducer
  if (-not (Test-MIRAssuranceReleaseProducer -Producer $producer -Context $Context)) {
    throw "Release seals may only be created by the protected-release workflow, environment, ref, and runner."
  }
  $commit = (& git -C $repo rev-parse HEAD).Trim()
  $branch = (& git -C $repo branch --show-current).Trim()
  $status = @(& git -C $repo status --porcelain --untracked-files=all)
  $nonGeneratedStatus = @($status | Where-Object {
    $path = if ($_.Length -ge 4) { $_.Substring(3).Replace("\", "/") } else { [string]$_ }
    $path -notlike "artifacts/assurance/*" -and
      $path -notlike "out/*" -and
      $path -notlike "approved-delta/*" -and
      $path -notlike ".mir/evidence/*"
  })
  if ($nonGeneratedStatus.Count -ne 0) {
    throw "Refusing to seal a dirty source tree. Commit the exact candidate source first."
  }
  if ([string]$plan.source_commit -ne $commit) { throw "Verification plan source commit is not the current source commit." }
  if ([string]$plan.candidate_descriptor_sha256 -ne [string](Get-MIRAssuranceCandidateDescriptor -Context $Context).descriptor_sha256) {
    throw "Verification plan candidate descriptor is not the current candidate."
  }
  $performanceEvidence = Test-MIRRuntimePerformanceEvidence `
    -RepoRoot $repo `
    -Candidate $Context.candidate `
    -PriorRelease $Context.prior_release `
    -FactorioBin $Context.factorio `
    -ExpectedSourceCommit $commit `
    -ExpectedBaselineVersion ([string]$Context.verification_profile.upgrade.from_version) `
    -ExpectedFactorioVersion ([string]$Context.verification_profile.qualification_factorio_version)
  $manualReview = Test-MIRManualReleaseAttestation `
    -RepoRoot $repo `
    -Candidate $Context.candidate `
    -FactorioBin $Context.factorio `
    -ExpectedSourceCommit $commit `
    -ExpectedFactorioVersion ([string]$Context.verification_profile.qualification_factorio_version)
  $sourceLockPath = Join-Path $repo ".mir\backport-source-lock.json"
  $canonicalDevAnchor = $commit
  if (Test-Path -LiteralPath $sourceLockPath -PathType Leaf) {
    $sourceLock = Get-Content -Raw -LiteralPath $sourceLockPath | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace([string]$sourceLock.canonical_dev_anchor)) {
      $canonicalDevAnchor = [string]$sourceLock.canonical_dev_anchor
    }
  }
  $domainManifest = Get-MIRAssuranceDomainManifest -Context $Context -RequireCandidate
  $qualificationRoot = Join-Path $repo ".mir\evidence\qualifications\$($Context.info.version)-factorio-$($Context.target)"
  New-Item -ItemType Directory -Force -Path $qualificationRoot | Out-Null
  $planSnapshotPath = Join-Path $qualificationRoot "verification-plan.json"
  $bundleSnapshotPath = Join-Path $qualificationRoot "evidence-bundle.json"
  Write-MIRAssuranceAtomicJson -Value $plan -Path $planSnapshotPath
  Write-MIRAssuranceAtomicJson -Value $bundle -Path $bundleSnapshotPath
  $seal = [ordered]@{
    schema=4
    state="SEALED-RC"
    release_status="NOT RELEASED"
    version=[string]$Context.info.version
    mir_version=[string]$Context.info.version
    factorio_target=$Context.target
    target=$Context.target
    canonical_dev_anchor=$canonicalDevAnchor
    branch=$branch
    source_commit=$commit
    source_tree=[string]$plan.source_tree
    source_clean=($nonGeneratedStatus.Count -eq 0)
    candidate=(Get-MIRAssuranceRepoRelativePath -Path $Context.candidate)
    candidate_sha256=(Get-MIRAssuranceSha256 -Path $Context.candidate)
    candidate_content_sha256=(Get-MIRAssuranceZipContentHash -Path $Context.candidate)
    candidate_descriptor_sha256=[string]$plan.candidate_descriptor_sha256
    candidate_domain_manifest_sha256=[string]$domainManifest.manifest_sha256
    package_source_sha256=(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssurancePackageFiles))
    target_profile_sha256=(Get-MIRAssuranceRepositoryFileHash -Path $targetsPath)
    verification_profile_sha256=(Get-MIRAssuranceSha256 -Path (Get-MIRAssuranceVerificationProfilePath -Target $Context.target))
    domain_policy_sha256=(Get-MIRAssuranceSha256 -Path $domainsPath)
    test_catalog_sha256=(Get-MIRAssuranceRepositoryFileHash -Path $catalogPath)
    validation_harness_sha256=(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssuranceHarnessFiles))
    trust_policy_sha256=(Get-MIRAssuranceSha256 -Path $trustPath)
    verification_plan=(Get-MIRAssuranceRepoRelativePath -Path $planSnapshotPath)
    verification_plan_sha256=(Get-MIRAssuranceSha256 -Path $planSnapshotPath)
    plan_material_sha256=[string]$plan.plan_material_sha256
    required_test_set_sha256=[string]$plan.required_test_set_sha256
    evidence_bundle=(Get-MIRAssuranceRepoRelativePath -Path $bundleSnapshotPath)
    evidence_bundle_sha256=(Get-MIRAssuranceSha256 -Path $bundleSnapshotPath)
    evidence_bundle_digest=[string]$bundle.bundle_sha256
    capsule_set_sha256=[string]$bundle.capsule_set_sha256
    performance_evidence=(Get-MIRAssuranceRepoRelativePath -Path $performanceEvidence.path)
    performance_evidence_sha256=[string]$performanceEvidence.sha256
    performance_status=[string]$performanceEvidence.status
    manual_review_attestation=(Get-MIRAssuranceRepoRelativePath -Path $manualReview.path)
    manual_review_attestation_sha256=[string]$manualReview.sha256
    manual_review_status=[string]$manualReview.status
    verifier_release_sha256=(Get-MIRAssuranceRunnerHash)
    producer_attestation=$producer
    sealed_at=(Get-Date).ToUniversalTime().ToString("o")
  }
  $seal["seal_sha256"] = Get-MIRAssuranceJsonHash -Value $seal
  $default = ".mir/evidence/candidate-seals/mir-$($Context.info.version)-factorio-$($Context.target).json"
  Write-MIRAssuranceJson -Value $seal -DefaultPath $default
}

function Invoke-MIRAssuranceCheckSeal {
  param([Parameter(Mandatory)]$Context)
  $sealPath = $Context.seal
  if (-not $sealPath -or -not (Test-Path -LiteralPath $sealPath -PathType Leaf)) { throw "check-seal requires --seal <path>." }
  $seal = Get-Content -Raw -LiteralPath $sealPath | ConvertFrom-Json
  if ([int]$seal.schema -ne 4) { throw "Candidate seal schema must be 4." }
  $candidate = Resolve-MIRAssurancePath -Path ([string]$seal.candidate)
  $planPath = Resolve-MIRAssurancePath -Path ([string]$seal.verification_plan)
  $bundlePath = Resolve-MIRAssurancePath -Path ([string]$seal.evidence_bundle)
  $performancePath = Resolve-MIRAssurancePath -Path ([string]$seal.performance_evidence)
  $manualReviewPath = Resolve-MIRAssurancePath -Path ([string]$seal.manual_review_attestation)
  $checks = [ordered]@{
    seal_digest=$false
    candidate_exists=(Test-Path -LiteralPath $candidate -PathType Leaf)
    candidate_sha256=$false
    candidate_content_sha256=$false
    candidate_descriptor_sha256=$false
    candidate_domain_manifest_sha256=$false
    package_source_sha256=$false
    target_profile_sha256=$false
    verification_profile_sha256=$false
    domain_policy_sha256=$false
    test_catalog_sha256=$false
    validation_harness_sha256=$false
    trust_policy_sha256=$false
    source_is_ancestor=$false
    source_tree=$false
    verification_plan_sha256=$false
    plan_material_sha256=$false
    required_test_set_sha256=$false
    evidence_bundle_sha256=$false
    evidence_bundle_digest=$false
    capsule_set_sha256=$false
    performance_evidence_sha256=$false
    performance_status=$false
    manual_review_attestation_sha256=$false
    manual_review_status=$false
    verifier_release_sha256=$false
    producer_attestation=$false
  }
  $sealMaterial = ConvertTo-MIRAssuranceOrderedMap -Object $seal
  $sealMaterial.Remove("seal_sha256")
  $checks.seal_digest=((Get-MIRAssuranceJsonHash -Value $sealMaterial) -eq [string]$seal.seal_sha256)
  if ($checks.candidate_exists) {
    $checks.candidate_sha256=((Get-MIRAssuranceSha256 -Path $candidate) -eq [string]$seal.candidate_sha256)
    $checks.candidate_content_sha256=((Get-MIRAssuranceZipContentHash -Path $candidate) -eq [string]$seal.candidate_content_sha256)
    $sealContext = $Context.PSObject.Copy()
    $sealContext.candidate = $candidate
    $checks.candidate_domain_manifest_sha256=([string](Get-MIRAssuranceDomainManifest -Context $sealContext -RequireCandidate).manifest_sha256 -eq [string]$seal.candidate_domain_manifest_sha256)
    $checks.candidate_descriptor_sha256=([string](Get-MIRAssuranceCandidateDescriptor -Context $sealContext).descriptor_sha256 -eq [string]$seal.candidate_descriptor_sha256)
  }
  $checks.package_source_sha256=((Get-MIRAssuranceTreeHash -Paths (Get-MIRAssurancePackageFiles)) -eq [string]$seal.package_source_sha256)
  $checks.target_profile_sha256=((Get-MIRAssuranceRepositoryFileHash -Path $targetsPath) -eq [string]$seal.target_profile_sha256)
  $checks.verification_profile_sha256=((Get-MIRAssuranceSha256 -Path (Get-MIRAssuranceVerificationProfilePath -Target $Context.target)) -eq [string]$seal.verification_profile_sha256)
  $checks.domain_policy_sha256=((Get-MIRAssuranceSha256 -Path $domainsPath) -eq [string]$seal.domain_policy_sha256)
  $checks.test_catalog_sha256=((Get-MIRAssuranceRepositoryFileHash -Path $catalogPath) -eq [string]$seal.test_catalog_sha256)
  $checks.validation_harness_sha256=((Get-MIRAssuranceTreeHash -Paths (Get-MIRAssuranceHarnessFiles)) -eq [string]$seal.validation_harness_sha256)
  $checks.trust_policy_sha256=((Get-MIRAssuranceSha256 -Path $trustPath) -eq [string]$seal.trust_policy_sha256)
  & git -C $repo merge-base --is-ancestor ([string]$seal.source_commit) HEAD
  $checks.source_is_ancestor=($LASTEXITCODE -eq 0)
  $sourceTree = @(& git -C $repo rev-parse "$([string]$seal.source_commit)^{tree}" 2>$null)
  $checks.source_tree=($LASTEXITCODE -eq 0 -and [string]$sourceTree[0] -eq [string]$seal.source_tree)
  if (Test-Path -LiteralPath $planPath -PathType Leaf) {
    $checks.verification_plan_sha256=((Get-MIRAssuranceSha256 -Path $planPath) -eq [string]$seal.verification_plan_sha256)
    if ($checks.verification_plan_sha256) {
      try {
        $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
        $checks.plan_material_sha256=([string]$plan.plan_material_sha256 -eq [string]$seal.plan_material_sha256)
        $checks.required_test_set_sha256=([string]$plan.required_test_set_sha256 -eq [string]$seal.required_test_set_sha256)
      } catch {}
    }
  }
  if (Test-Path -LiteralPath $bundlePath -PathType Leaf) {
    $checks.evidence_bundle_sha256=((Get-MIRAssuranceSha256 -Path $bundlePath) -eq [string]$seal.evidence_bundle_sha256)
    if ($checks.evidence_bundle_sha256) {
      try {
        $bundle = Get-Content -Raw -LiteralPath $bundlePath | ConvertFrom-Json
        $bundleMaterial = ConvertTo-MIRAssuranceOrderedMap -Object $bundle
        $recordedBundleDigest = [string]$bundleMaterial.bundle_sha256
        $bundleMaterial.Remove("bundle_sha256")
        $checks.evidence_bundle_digest=(
          $recordedBundleDigest -eq [string]$seal.evidence_bundle_digest -and
          (Get-MIRAssuranceJsonHash -Value $bundleMaterial) -eq $recordedBundleDigest -and
          [string]$bundle.status -eq "passed"
        )
        $checks.capsule_set_sha256=(
          [string]$bundle.capsule_set_sha256 -eq [string]$seal.capsule_set_sha256 -and
          (Get-MIRAssuranceJsonHash -Value @($bundle.capsule_set)) -eq [string]$bundle.capsule_set_sha256
        )
      } catch {}
    }
  }
  if (Test-Path -LiteralPath $performancePath -PathType Leaf) {
    $checks.performance_evidence_sha256=((Get-MIRAssuranceSha256 -Path $performancePath) -eq [string]$seal.performance_evidence_sha256)
    if ($checks.performance_evidence_sha256) {
      try {
        $performance = Get-Content -Raw -LiteralPath $performancePath | ConvertFrom-Json
        $checks.performance_status=(
          [string]$seal.performance_status -eq "passed" -and
          [string]$performance.status -eq "passed" -and
          [string]$performance.candidate.archive_sha256 -eq [string]$seal.candidate_sha256 -and
          [string]$performance.candidate.package_content_sha256 -eq [string]$seal.candidate_content_sha256 -and
          [string]$performance.candidate.source_commit -eq [string]$seal.source_commit
        )
      } catch {}
    }
  }
  if (Test-Path -LiteralPath $manualReviewPath -PathType Leaf) {
    $checks.manual_review_attestation_sha256=((Get-MIRAssuranceSha256 -Path $manualReviewPath) -eq [string]$seal.manual_review_attestation_sha256)
    if ($checks.manual_review_attestation_sha256) {
      try {
        $manualReview = Get-Content -Raw -LiteralPath $manualReviewPath | ConvertFrom-Json
        $manualMaterial = ConvertTo-MIRReleaseOrderedMap -Object $manualReview
        $manualMaterial.Remove("attestation_sha256")
        $manualSelfHash = Get-MIRReleaseTextSha256 -Text ($manualMaterial | ConvertTo-Json -Depth 40 -Compress)
        $checks.manual_review_status=(
          [string]$seal.manual_review_status -eq "passed" -and
          [string]$manualReview.status -eq "passed" -and
          [string]$manualReview.candidate_sha256 -eq [string]$seal.candidate_sha256 -and
          [string]$manualReview.candidate_content_sha256 -eq [string]$seal.candidate_content_sha256 -and
          [string]$manualReview.source_commit -eq [string]$seal.source_commit -and
          [string]$manualReview.attestation_sha256 -eq $manualSelfHash
        )
      } catch {}
    }
  }
  $checks.verifier_release_sha256=((Get-MIRAssuranceRunnerHash) -eq [string]$seal.verifier_release_sha256)
  $checks.producer_attestation=(Test-MIRAssuranceReleaseProducer `
    -Producer $seal.producer_attestation `
    -Context $Context `
    -ExpectedCommit ([string]$seal.source_commit))
  $passed = @($checks.Values | Where-Object { -not $_ }).Count -eq 0
  $result = [ordered]@{ schema=1; status=if ($passed) { "passed" } else { "failed" }; seal=$sealPath; checks=$checks }
  Write-MIRAssuranceJson -Value $result
  if (-not $passed) { throw "Candidate seal verification failed." }
}

function Invoke-MIRAssuranceSelfTest {
  param([Parameter(Mandatory)]$Context)
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

  $baseMaterial = [ordered]@{test="a"; candidate="a"; binary="a"; harness="a"; settings="a"}
  $base = Get-MIRAssuranceJsonHash -Value $baseMaterial
  foreach ($field in @("candidate", "binary", "harness", "settings")) {
    $changed = [ordered]@{test="a"; candidate="a"; binary="a"; harness="a"; settings="a"}
    $changed[$field] = "b"
    if ((Get-MIRAssuranceJsonHash -Value $changed) -eq $base) { throw "Evidence invalidation self-test failed for $field." }
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

  $selfTestId = "self-test.synthetic"
  $selfTestKey = Get-MIRAssuranceTextHash -Text ([guid]::NewGuid().ToString("N"))
  $fingerprint = [ordered]@{
    schema=$evidenceSchema
    test_id=$selfTestId
    target=[string]$Context.target
    input_key=$selfTestKey
    fingerprint_sha256=$selfTestKey
    definition_sha256=(Get-MIRAssuranceTextHash -Text "definition")
  }
  $paths = Get-MIRAssuranceEvidencePaths -TestId $selfTestId -InputKey $selfTestKey
  $selfTestArtifactRoot = Join-Path $paths.root "work\synthetic"
  New-Item -ItemType Directory -Force -Path $selfTestArtifactRoot | Out-Null
  $selfTestResultPath = Join-Path $selfTestArtifactRoot "result.json"
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
  $emptyLogHash = Get-MIRAssuranceTextHash -Text ""
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
    stdout_sha256=$emptyLogHash
    stderr_sha256=$emptyLogHash
    log_digest=$emptyLogHash
    started_at=(Get-Date).ToUniversalTime().ToString("o")
    completed_at=(Get-Date).ToUniversalTime().ToString("o")
    duration_seconds=0
    message=""
  }
  $null = Write-MIRAssuranceAttempt -Capsule $capsule
  if ($null -eq (Get-MIRAssuranceReusableEvidence -Fingerprint $fingerprint -Context $Context)) { throw "Passing exact-input evidence was not reusable." }
  $fakeCapsule = ($capsule | ConvertTo-Json -Depth 40) | ConvertFrom-Json
  $fakeCapsule.result = $null
  $fakeCapsule.result_digest = Get-MIRAssuranceCapsuleDigest -Capsule $fakeCapsule
  if ((Test-MIRAssuranceCapsule -Capsule $fakeCapsule -Fingerprint $fingerprint -Context $Context).valid) {
    throw "A fake passing capsule without structured result evidence was accepted."
  }
  $untrustedCapsule = ($capsule | ConvertTo-Json -Depth 40) | ConvertFrom-Json
  $untrustedCapsule.producer.trust_class = "untrusted-pr"
  $untrustedCapsule.result_digest = Get-MIRAssuranceCapsuleDigest -Capsule $untrustedCapsule
  if ((Test-MIRAssuranceCapsule -Capsule $untrustedCapsule -Fingerprint $fingerprint -Context $Context).valid) {
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

  $freshnessProducer = Get-MIRAssuranceProducer
  $freshnessGeneratedAt = (Get-Date).ToUniversalTime().ToString("o")
  $freshnessTest = [pscustomobject][ordered]@{
    id="self-test.freshness"
    force_fresh=$true
    minimum_completed_at=$freshnessGeneratedAt
    required_run_id=[string]$freshnessProducer.run_id
    required_run_attempt=[string]$freshnessProducer.run_attempt
  }
  $freshnessPlan = [pscustomobject][ordered]@{
    producer=$freshnessProducer
    source_commit=[string]$freshnessProducer.commit
    generated_at=$freshnessGeneratedAt
    reuse_enabled=$false
    rerun_tests=@()
    tests=@($freshnessTest)
  }
  $null = Assert-MIRAssurancePlanFreshnessBinding -Plan $freshnessPlan -Context $Context
  $freshnessTest.required_run_id = "tampered-run"
  $tamperedFreshnessRejected = $false
  try {
    $null = Assert-MIRAssurancePlanFreshnessBinding -Plan $freshnessPlan -Context $Context
  } catch { $tamperedFreshnessRejected = $true }
  if (-not $tamperedFreshnessRejected) {
    throw "Tampered fresh-evidence run binding was accepted."
  }
  if ([string]$Context.trust_class -eq "untrusted-local") {
    $freshnessTest.required_run_id = "local-plan-$([guid]::NewGuid().ToString('N'))"
    $boundProducer = Get-MIRAssuranceEvidenceProducer -Test $freshnessTest -Plan $freshnessPlan -Context $Context
    if ([string]$boundProducer.run_id -ne [string]$freshnessTest.required_run_id -or
        [string]$boundProducer.run_attempt -ne [string]$freshnessTest.required_run_attempt) {
      throw "A local worker did not adopt the plan-owned fresh-evidence identity."
    }
    if ($boundProducer.Contains("Count") -or
        [string]::IsNullOrWhiteSpace([string]$boundProducer.verifier_sha256) -or
        [string]::IsNullOrWhiteSpace([string]$boundProducer.policy_sha256)) {
      throw "A local worker serialized a dictionary wrapper instead of the producer attestation."
    }
  }

  $resolvedSelfTestRoot = [IO.Path]::GetFullPath($paths.root)
  $resolvedEvidenceRoot = [IO.Path]::GetFullPath($evidenceRoot).TrimEnd("\") + "\"
  if (-not $resolvedSelfTestRoot.StartsWith($resolvedEvidenceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove assurance self-test evidence outside the evidence root."
  }
  Remove-Item -LiteralPath $resolvedSelfTestRoot -Recurse -Force

  $runningKey = Get-MIRAssuranceTextHash -Text ([guid]::NewGuid().ToString("N"))
  $runningFingerprint = [ordered]@{
    schema=$evidenceSchema
    test_id="self-test.running"
    target=[string]$Context.target
    input_key=$runningKey
    fingerprint_sha256=$runningKey
    definition_sha256=(Get-MIRAssuranceTextHash -Text "running-definition")
  }
  $running = Write-MIRAssuranceRunningEvidence -Fingerprint $runningFingerprint -Context $Context
  if ($null -eq (Get-MIRAssuranceRunningEvidence -Fingerprint $runningFingerprint -Context $Context)) {
    throw "Matching live worker evidence was not adoptable."
  }
  $running.process_id = [int]::MaxValue
  $runningPaths = Get-MIRAssuranceEvidencePaths -TestId $runningFingerprint.test_id -InputKey $runningFingerprint.input_key
  [IO.File]::WriteAllText($runningPaths.running, (($running | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
  if ($null -ne (Get-MIRAssuranceRunningEvidence -Fingerprint $runningFingerprint -Context $Context)) {
    throw "Dead local worker evidence was incorrectly adoptable."
  }
  if (Test-Path -LiteralPath $runningPaths.root) {
    $resolvedRunningRoot = [IO.Path]::GetFullPath($runningPaths.root)
    if (-not $resolvedRunningRoot.StartsWith($resolvedEvidenceRoot, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove running self-test evidence outside the evidence root."
    }
    Remove-Item -LiteralPath $resolvedRunningRoot -Recurse -Force
  }

  $emptyPlanRejected = $false
  try {
    $null = Complete-MIRAssurancePlan -Plan ([ordered]@{tests=@()}) -Context $Context
  } catch { $emptyPlanRejected = $true }
  if (-not $emptyPlanRejected) { throw "Empty verification plan was accepted." }

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

  Write-Host "[ok] MIR assurance classifier, plan closure, structured evidence, trust, freshness binding, blocking, and version-only reuse tests passed."
}
