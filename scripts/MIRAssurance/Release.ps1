. (Join-Path $PSScriptRoot "Hashing.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "validation\ReleaseAttestations.ps1")

function Get-MIRAssuranceCandidateArchiveIdentity {
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Candidate does not exist: $Path" }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entryCount = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith("/") }).Count
  } finally {
    $archive.Dispose()
  }
  return [pscustomobject]@{
    bytes = (Get-Item -LiteralPath $Path).Length
    entries = $entryCount
    sha256 = Get-MIRAssuranceSha256 -Path $Path
    content_sha256 = Get-MIRAssuranceZipContentHash -Path $Path
  }
}

function Get-MIRAssuranceReleaseCandidateAuthority {
  param([Parameter(Mandatory)]$Context)

  $ledgerPath = Join-Path $repo ".mir\releases.json"
  $ledger = Get-Content -Raw -LiteralPath $ledgerPath | ConvertFrom-Json
  if ([int]$ledger.schema -ne 1 -or [string]$ledger.authority -ne "canonical-release-ledger") {
    throw "Canonical release ledger is invalid."
  }
  $targetKey = "factorio-$($Context.target)"
  $property = $ledger.development.PSObject.Properties[$targetKey]
  if ($null -eq $property) { throw "Canonical release ledger has no development authority for $targetKey." }
  $authority = $property.Value
  if ([string]$authority.mir_version -ne [string]$Context.info.version) {
    throw "Release authority version does not match the candidate version."
  }
  if ([string]$authority.candidate_id -notmatch '^C[1-9][0-9]*$') {
    throw "Release authority candidate_id is invalid."
  }
  if ([string]$authority.package_source_commit -notmatch '^[0-9a-f]{40}$') {
    throw "Release authority package_source_commit must be a full lowercase Git commit."
  }
  foreach ($field in @("package_source_sha256", "archive_sha256", "package_content_sha256")) {
    if ([string]$authority.$field -notmatch '^[0-9A-F]{64}$') {
      throw "Release authority $field must be an uppercase SHA-256 digest."
    }
  }
  $material = $authority.package_source_material
  $materialAlgorithm = [string]$material.hash_algorithm
  $legacyMaterial = $materialAlgorithm -eq "git-index-with-captured-worktree-v1" -and
    [string]$material.source_parent_commit -match '^[0-9a-f]{40}$' -and
    @($material.changed_files).Count -gt 0
  $cleanMaterial = $materialAlgorithm -eq "git-commit-normalized-package-v1" -and
    [string]$material.source_tree -match '^[0-9a-f]{40}$' -and
    [int]$material.file_count -gt 0
  if ([int]$material.schema -ne 1 -or (-not $legacyMaterial -and -not $cleanMaterial)) {
    throw "Release authority package_source_material is invalid."
  }
  if ([long]$authority.archive_bytes -le 0) { throw "Release authority archive_bytes must be positive." }
  $null = Resolve-MIRAssuranceCommit -Commit ([string]$authority.package_source_commit)
  return $authority
}

function Get-MIRAssuranceCommitCandidateIdentity {
  param([Parameter(Mandatory)][string]$Commit)

  $resolvedCommit = Resolve-MIRAssuranceCommit -Commit $Commit
  $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-seal-source-" + [guid]::NewGuid().ToString("N"))
  $sourceRoot = Join-Path $temporaryRoot "source"
  $sourceArchive = Join-Path $temporaryRoot "source.zip"
  try {
    New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
    . (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
    $archivePaths = @(
      @(Get-MIRPackageSourceRoots)
      "scripts/Build-MIRPackage.ps1"
      "scripts/validation/PackageIdentity.ps1"
    )
    & git -C $repo archive --format=zip --output=$sourceArchive $resolvedCommit -- @archivePaths 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Unable to extract committed package inputs for $resolvedCommit." }
    Expand-Archive -LiteralPath $sourceArchive -DestinationPath $sourceRoot
    $powerShell = (Get-Process -Id $PID).Path
    & $powerShell -NoProfile -NonInteractive -File (Join-Path $sourceRoot "scripts\Build-MIRPackage.ps1") -OutputDir "authority-dist" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Deterministic package reconstruction failed for $resolvedCommit." }
    $info = Get-Content -Raw -LiteralPath (Join-Path $sourceRoot "info.json") | ConvertFrom-Json
    $candidate = Join-Path $sourceRoot "authority-dist\$($info.name)_$($info.version).zip"
    $identity = Get-MIRAssuranceCandidateArchiveIdentity -Path $candidate
    return [pscustomobject]@{
      commit = $resolvedCommit
      bytes = [long]$identity.bytes
      entries = [int]$identity.entries
      sha256 = [string]$identity.sha256
      content_sha256 = [string]$identity.content_sha256
    }
  } finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
      Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
  }
}

function Get-MIRAssuranceSealSourceAuthority {
  param(
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$QualificationCommit
  )

  $qualification = Resolve-MIRAssuranceCommit -Commit $QualificationCommit
  $authority = Get-MIRAssuranceReleaseCandidateAuthority -Context $Context
  $packageCommit = Resolve-MIRAssuranceCommit -Commit ([string]$authority.package_source_commit)
  & git -C $repo merge-base --is-ancestor $packageCommit $qualification
  if ($LASTEXITCODE -ne 0) { throw "Package-source commit is not an ancestor of the qualification commit." }
  if (-not (Test-MIRAssurancePackageRootsEqual -ReferenceCommit $packageCommit -DifferenceCommit $qualification)) {
    throw "Package-visible paths changed between package source and qualification."
  }
  $packageMaterial = Get-MIRAssurancePackageAuthorityHash -PackageSourceCommit $packageCommit -ContentCommit $packageCommit -Material $authority.package_source_material
  $qualificationMaterial = Get-MIRAssurancePackageAuthorityHash -PackageSourceCommit $packageCommit -ContentCommit $qualification -Material $authority.package_source_material
  if ([string]$packageMaterial.sha256 -ne [string]$authority.package_source_sha256) {
    throw "Package-source commit does not reproduce the canonical package-source identity."
  }
  if ([string]$qualificationMaterial.sha256 -ne [string]$authority.package_source_sha256) {
    throw "Qualification commit does not preserve the canonical package-source identity."
  }
  $candidateIdentity = Get-MIRAssuranceCandidateArchiveIdentity -Path $Context.candidate
  if ([long]$candidateIdentity.bytes -ne [long]$authority.archive_bytes -or
      [string]$candidateIdentity.sha256 -ne [string]$authority.archive_sha256 -or
      [string]$candidateIdentity.content_sha256 -ne [string]$authority.package_content_sha256) {
    throw "Candidate archive does not match canonical release authority."
  }
  $packageBuild = Get-MIRAssuranceCommitCandidateIdentity -Commit $packageCommit
  $qualificationBuild = Get-MIRAssuranceCommitCandidateIdentity -Commit $qualification
  foreach ($build in @($packageBuild, $qualificationBuild)) {
    if ([long]$build.bytes -ne [long]$candidateIdentity.bytes -or
        [int]$build.entries -ne [int]$candidateIdentity.entries -or
        [string]$build.sha256 -ne [string]$candidateIdentity.sha256 -or
        [string]$build.content_sha256 -ne [string]$candidateIdentity.content_sha256) {
      throw "Commit $($build.commit) does not reproduce the exact candidate archive and content identities."
    }
  }
  $qualificationTree = @(& git -C $repo rev-parse "$qualification^{tree}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $qualificationTree.Count -ne 1) {
    throw "Unable to resolve the qualification source tree."
  }
  return [pscustomobject]@{
    candidate = $authority
    package_source_commit = $packageCommit
    package_source_sha256 = [string]$authority.package_source_sha256
    package_source_material = $authority.package_source_material
    qualification_source_commit = $qualification
    qualification_source_tree = [string]$qualificationTree[0]
    candidate_identity = $candidateIdentity
    package_source_build = $packageBuild
    qualification_source_build = $qualificationBuild
  }
}

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
  $sourceAuthority = Get-MIRAssuranceSealSourceAuthority -Context $Context -QualificationCommit $commit
  if ([string]$plan.source_tree -ne [string]$sourceAuthority.qualification_source_tree) {
    throw "Verification plan source tree is not the qualification source tree."
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
    candidate_id=$false
    candidate_authority=$false
    candidate_sha256=$false
    candidate_content_sha256=$false
    candidate_descriptor_sha256=$false
    candidate_domain_manifest_sha256=$false
    source_aliases=$false
    package_source_is_ancestor=$false
    package_source_identity=$false
    qualification_package_source_identity=$false
    package_roots_unchanged=$false
    package_roots_unchanged_to_head=$false
    package_source_candidate=$false
    qualification_source_candidate=$false
    target_profile_sha256=$false
    verification_profile_sha256=$false
    domain_policy_sha256=$false
    test_catalog_sha256=$false
    validation_harness_sha256=$false
    trust_policy_sha256=$false
    source_is_ancestor=$false
    source_tree=$false
    qualification_source_is_ancestor=$false
    qualification_source_tree=$false
    verification_plan_sha256=$false
    verification_plan_source=$false
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
  $candidateIdentity = $null
  if ($checks.candidate_exists) {
    $candidateIdentity = Get-MIRAssuranceCandidateArchiveIdentity -Path $candidate
    $checks.candidate_sha256=([string]$candidateIdentity.sha256 -eq [string]$seal.candidate_sha256)
    $checks.candidate_content_sha256=([string]$candidateIdentity.content_sha256 -eq [string]$seal.candidate_content_sha256)
    $sealContext = $Context.PSObject.Copy()
    $sealContext.candidate = $candidate
    $checks.candidate_domain_manifest_sha256=([string](Get-MIRAssuranceDomainManifest -Context $sealContext -RequireCandidate).manifest_sha256 -eq [string]$seal.candidate_domain_manifest_sha256)
    $checks.candidate_descriptor_sha256=([string](Get-MIRAssuranceCandidateDescriptor -Context $sealContext).descriptor_sha256 -eq [string]$seal.candidate_descriptor_sha256)
    try {
      $candidateAuthority = Get-MIRAssuranceReleaseCandidateAuthority -Context $sealContext
      $checks.candidate_id=([string]$candidateAuthority.candidate_id -eq [string]$seal.candidate_id)
      $checks.candidate_authority=(
        [string]$candidateAuthority.package_source_commit -eq [string]$seal.package_source_commit -and
        [string]$candidateAuthority.package_source_sha256 -eq [string]$seal.package_source_sha256 -and
        (Get-MIRAssuranceJsonHash -Value $candidateAuthority.package_source_material) -eq (Get-MIRAssuranceJsonHash -Value $seal.package_source_material) -and
        [long]$candidateAuthority.archive_bytes -eq [long]$candidateIdentity.bytes -and
        [string]$candidateAuthority.archive_sha256 -eq [string]$candidateIdentity.sha256 -and
        [string]$candidateAuthority.package_content_sha256 -eq [string]$candidateIdentity.content_sha256
      )
    } catch {}
  }
  $checks.source_aliases=(
    [string]$seal.source_commit -eq [string]$seal.qualification_source_commit -and
    [string]$seal.source_tree -eq [string]$seal.qualification_source_tree
  )
  try {
    $packageCommit = Resolve-MIRAssuranceCommit -Commit ([string]$seal.package_source_commit)
    $qualificationCommit = Resolve-MIRAssuranceCommit -Commit ([string]$seal.qualification_source_commit)
    & git -C $repo merge-base --is-ancestor $packageCommit $qualificationCommit
    $checks.package_source_is_ancestor=($LASTEXITCODE -eq 0)
    $checks.package_roots_unchanged=(Test-MIRAssurancePackageRootsEqual -ReferenceCommit $packageCommit -DifferenceCommit $qualificationCommit)
    $checks.package_roots_unchanged_to_head=(Test-MIRAssurancePackageRootsEqual -ReferenceCommit $packageCommit -DifferenceCommit HEAD)
    $packageMaterial = Get-MIRAssurancePackageAuthorityHash -PackageSourceCommit $packageCommit -ContentCommit $packageCommit -Material $seal.package_source_material
    $qualificationMaterial = Get-MIRAssurancePackageAuthorityHash -PackageSourceCommit $packageCommit -ContentCommit $qualificationCommit -Material $seal.package_source_material
    $checks.package_source_identity=([string]$packageMaterial.sha256 -eq [string]$seal.package_source_sha256)
    $checks.qualification_package_source_identity=([string]$qualificationMaterial.sha256 -eq [string]$seal.package_source_sha256)
    if ($null -ne $candidateIdentity) {
      $packageBuild = Get-MIRAssuranceCommitCandidateIdentity -Commit $packageCommit
      $qualificationBuild = Get-MIRAssuranceCommitCandidateIdentity -Commit $qualificationCommit
      $checks.package_source_candidate=(
        [long]$packageBuild.bytes -eq [long]$candidateIdentity.bytes -and
        [int]$packageBuild.entries -eq [int]$candidateIdentity.entries -and
        [string]$packageBuild.sha256 -eq [string]$candidateIdentity.sha256 -and
        [string]$packageBuild.content_sha256 -eq [string]$candidateIdentity.content_sha256
      )
      $checks.qualification_source_candidate=(
        [long]$qualificationBuild.bytes -eq [long]$candidateIdentity.bytes -and
        [int]$qualificationBuild.entries -eq [int]$candidateIdentity.entries -and
        [string]$qualificationBuild.sha256 -eq [string]$candidateIdentity.sha256 -and
        [string]$qualificationBuild.content_sha256 -eq [string]$candidateIdentity.content_sha256
      )
    }
  } catch {}
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
  & git -C $repo merge-base --is-ancestor ([string]$seal.qualification_source_commit) HEAD
  $checks.qualification_source_is_ancestor=($LASTEXITCODE -eq 0)
  $qualificationTree = @(& git -C $repo rev-parse "$([string]$seal.qualification_source_commit)^{tree}" 2>$null)
  $checks.qualification_source_tree=(
    $LASTEXITCODE -eq 0 -and
    [string]$qualificationTree[0] -eq [string]$seal.qualification_source_tree
  )
  if (Test-Path -LiteralPath $planPath -PathType Leaf) {
    $checks.verification_plan_sha256=((Get-MIRAssuranceSha256 -Path $planPath) -eq [string]$seal.verification_plan_sha256)
    if ($checks.verification_plan_sha256) {
      try {
        $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
        $checks.verification_plan_source=(
          [string]$plan.source_commit -eq [string]$seal.qualification_source_commit -and
          [string]$plan.source_tree -eq [string]$seal.qualification_source_tree
        )
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
    if ([string]$authority.candidate_id -ne "C6" -or
        [string]$packageMaterial.sha256 -ne [string]$authority.package_source_sha256 -or
        [string]$qualificationMaterial.sha256 -ne [string]$authority.package_source_sha256 -or
        [int]$packageMaterial.file_count -ne 231 -or
        -not (Test-MIRAssurancePackageRootsEqual -ReferenceCommit ([string]$authority.package_source_commit) -DifferenceCommit $qualificationCommit)) {
      throw "C6 package-source and qualification-source authority self-test failed."
    }
    $candidateIdentity = Get-MIRAssuranceCandidateArchiveIdentity -Path $Context.candidate
    if ([long]$candidateIdentity.bytes -ne [long]$authority.archive_bytes -or
        [string]$candidateIdentity.sha256 -ne [string]$authority.archive_sha256 -or
        [string]$candidateIdentity.content_sha256 -ne [string]$authority.package_content_sha256 -or
        (Get-MIRAssurancePackageSourceHash) -ne [string]$authority.package_source_sha256) {
      throw "C6 candidate, normalized content, and current package-source identities do not match release authority."
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
