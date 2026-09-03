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
  $branch = (@(& git -C $repo branch --show-current) -join "").Trim()
  $status = @(& git -C $repo status --porcelain --untracked-files=all)
  $nonGeneratedStatus = @($status | Where-Object {
    $path = if ($_.Length -ge 4) { $_.Substring(3).Replace("\", "/") } else { [string]$_ }
    $path -notlike "build/results/assurance/*" -and
      $path -notlike "build/results/*" -and
      $path -notlike ".mir/releases/deltas/*" -and
      $path -notlike ".mir/evidence/*"
  })
  if ($nonGeneratedStatus.Count -ne 0) {
    throw "Refusing to seal a dirty source tree. Commit the exact candidate source first."
  }
  if ([string]$plan.source_commit -ne $commit) { throw "Verification plan source commit is not the current source commit." }
  if ([string]$plan.candidate_descriptor_sha256 -ne [string](Get-MIRAssuranceCandidateDescriptor -Context $Context).descriptor_sha256) {
    throw "Verification plan candidate descriptor is not the current candidate."
  }
  $sourceAuthority = Get-MIRAssuranceSealSourceAuthority -Context $Context -QualificationCommit $commit
  if ([string]$plan.source_tree -ne [string]$sourceAuthority.qualification_source_tree) {
    throw "Verification plan source tree is not the qualification source tree."
  }
  $performanceArtifact = Get-MIRAssurancePerformanceEvidenceArtifact -Bundle $bundle
  $performanceArtifactPath = Resolve-MIRAssurancePath -Path ([string]$performanceArtifact.path)
  $performanceRecord = Get-Content -Raw -LiteralPath $performanceArtifactPath | ConvertFrom-Json
  $performanceSourceCommit = Resolve-MIRAssuranceCommit -Commit ([string]$performanceRecord.candidate.source_commit)
  & git -C $repo merge-base --is-ancestor $performanceSourceCommit $commit
  if ($LASTEXITCODE -ne 0) {
    throw "Runtime performance evidence source is not an ancestor of the qualification source."
  }
  if (-not (Test-MIRAssurancePackageRootsEqual `
      -ReferenceCommit ([string]$sourceAuthority.package_source_commit) `
      -DifferenceCommit $performanceSourceCommit)) {
    throw "Runtime performance evidence source does not preserve the candidate package roots."
  }
  $performanceSourceBuild = Get-MIRAssuranceCommitCandidateIdentity -Commit $performanceSourceCommit
  if ([long]$performanceSourceBuild.bytes -ne [long]$sourceAuthority.candidate_identity.bytes -or
      [int]$performanceSourceBuild.entries -ne [int]$sourceAuthority.candidate_identity.entries -or
      [string]$performanceSourceBuild.sha256 -ne [string]$sourceAuthority.candidate_identity.sha256 -or
      [string]$performanceSourceBuild.content_sha256 -ne [string]$sourceAuthority.candidate_identity.content_sha256) {
    throw "Runtime performance evidence source does not reproduce the exact candidate."
  }
  $null = Test-MIRRuntimePerformanceEvidence `
    -RepoRoot $repo `
    -Path $performanceArtifactPath `
    -Candidate $Context.candidate `
    -PriorRelease $Context.prior_release `
    -FactorioBin $Context.factorio `
    -ExpectedSourceCommit $performanceSourceCommit `
    -ExpectedBaselineVersion ([string]$Context.verification_profile.upgrade.from_version) `
    -ExpectedFactorioVersion ([string]$Context.verification_profile.qualification_factorio_version)
  $manualReview = Test-MIRManualReleaseAttestation `
    -RepoRoot $repo `
    -Candidate $Context.candidate `
    -FactorioBin $Context.factorio `
    -ExpectedSourceCommit ([string]$sourceAuthority.package_source_commit) `
    -ExpectedFactorioVersion ([string]$Context.verification_profile.qualification_factorio_version)
  $sourceLockPath = Join-Path $repo ".mir\backport-source-lock.json"
  $canonicalDevAnchor = $commit
  if (Test-Path -LiteralPath $sourceLockPath -PathType Leaf) {
    $sourceLock = Get-Content -Raw -LiteralPath $sourceLockPath | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace([string]$sourceLock.canonical_dev_anchor)) {
      $canonicalDevAnchor = [string]$sourceLock.canonical_dev_anchor
    }
  }
  $qualificationRoot = Join-Path $repo ".mir\evidence\qualifications\$($Context.info.version)-factorio-$($Context.target)"
  New-Item -ItemType Directory -Force -Path $qualificationRoot | Out-Null
  $performanceEvidencePath = Join-Path $qualificationRoot "performance-regression.json"
  Copy-Item -LiteralPath $performanceArtifactPath -Destination $performanceEvidencePath -Force
  if ((Get-MIRAssuranceSha256 -Path $performanceEvidencePath) -ne [string]$performanceArtifact.sha256) {
    throw "Durable performance evidence differs from the exact captured assurance artifact."
  }
  $performanceEvidence = Test-MIRRuntimePerformanceEvidence `
    -RepoRoot $repo `
    -Path $performanceEvidencePath `
    -Candidate $Context.candidate `
    -PriorRelease $Context.prior_release `
    -FactorioBin $Context.factorio `
    -ExpectedSourceCommit $performanceSourceCommit `
    -ExpectedBaselineVersion ([string]$Context.verification_profile.upgrade.from_version) `
    -ExpectedFactorioVersion ([string]$Context.verification_profile.qualification_factorio_version)
  $domainManifest = Get-MIRAssuranceDomainManifest -Context $Context -RequireCandidate
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
    candidate_id=[string]$sourceAuthority.candidate.candidate_id
    package_source_commit=[string]$sourceAuthority.package_source_commit
    package_source_sha256=[string]$sourceAuthority.package_source_sha256
    package_source_material=$sourceAuthority.package_source_material
    qualification_source_commit=[string]$sourceAuthority.qualification_source_commit
    qualification_source_tree=[string]$sourceAuthority.qualification_source_tree
    source_commit=[string]$sourceAuthority.qualification_source_commit
    source_tree=[string]$sourceAuthority.qualification_source_tree
    source_clean=($nonGeneratedStatus.Count -eq 0)
    candidate=(Get-MIRAssuranceRepoRelativePath -Path $Context.candidate)
    candidate_sha256=[string]$sourceAuthority.candidate_identity.sha256
    candidate_content_sha256=[string]$sourceAuthority.candidate_identity.content_sha256
    candidate_descriptor_sha256=[string]$plan.candidate_descriptor_sha256
    candidate_domain_manifest_sha256=[string]$domainManifest.manifest_sha256
    target_profile_sha256=(Get-MIRAssuranceRepositoryFileHash -Path $targetsPath)
    verification_profile_sha256=(Get-MIRAssuranceCanonicalJsonFileHash -Path (Get-MIRAssuranceVerificationProfilePath -Target $Context.target))
    domain_policy_sha256=(Get-MIRAssuranceCanonicalJsonFileHash -Path $domainsPath)
    test_catalog_sha256=(Get-MIRAssuranceRepositoryFileHash -Path $catalogPath)
    validation_harness_sha256=(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssuranceHarnessFiles))
    trust_policy_sha256=(Get-MIRAssuranceCanonicalJsonFileHash -Path (Get-MIRAssuranceCanonicalTrustPolicyPath))
    verification_plan=(Get-MIRAssuranceRepoRelativePath -Path $planSnapshotPath)
    verification_plan_sha256=(Get-MIRAssuranceSha256 -Path $planSnapshotPath)
    plan_material_sha256=[string]$plan.plan_material_sha256
    required_test_set_sha256=[string]$plan.required_test_set_sha256
    evidence_bundle=(Get-MIRAssuranceRepoRelativePath -Path $bundleSnapshotPath)
    evidence_bundle_sha256=(Get-MIRAssuranceSha256 -Path $bundleSnapshotPath)
    evidence_bundle_digest=[string]$bundle.bundle_sha256
    capsule_set_sha256=[string]$bundle.capsule_set_sha256
    performance_source_commit=$performanceSourceCommit
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
