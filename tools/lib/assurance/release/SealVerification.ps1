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
    performance_source_is_ancestor=$false
    performance_package_roots_unchanged=$false
    performance_source_candidate=$false
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
    $performanceCommit = Resolve-MIRAssuranceCommit -Commit ([string]$seal.performance_source_commit)
    & git -C $repo merge-base --is-ancestor $packageCommit $qualificationCommit
    $checks.package_source_is_ancestor=($LASTEXITCODE -eq 0)
    & git -C $repo merge-base --is-ancestor $performanceCommit $qualificationCommit
    $checks.performance_source_is_ancestor=($LASTEXITCODE -eq 0)
    $checks.package_roots_unchanged=(Test-MIRAssurancePackageRootsEqual -ReferenceCommit $packageCommit -DifferenceCommit $qualificationCommit)
    $checks.package_roots_unchanged_to_head=(Test-MIRAssurancePackageRootsEqual -ReferenceCommit $packageCommit -DifferenceCommit HEAD)
    $checks.performance_package_roots_unchanged=(Test-MIRAssurancePackageRootsEqual -ReferenceCommit $packageCommit -DifferenceCommit $performanceCommit)
    $packageMaterial = Get-MIRAssurancePackageAuthorityHash -PackageSourceCommit $packageCommit -ContentCommit $packageCommit -Material $seal.package_source_material
    $qualificationMaterial = Get-MIRAssurancePackageAuthorityHash -PackageSourceCommit $packageCommit -ContentCommit $qualificationCommit -Material $seal.package_source_material
    $checks.package_source_identity=([string]$packageMaterial.sha256 -eq [string]$seal.package_source_sha256)
    $checks.qualification_package_source_identity=([string]$qualificationMaterial.sha256 -eq [string]$seal.package_source_sha256)
    if ($null -ne $candidateIdentity) {
      $packageBuild = Get-MIRAssuranceCommitCandidateIdentity -Commit $packageCommit
      $qualificationBuild = Get-MIRAssuranceCommitCandidateIdentity -Commit $qualificationCommit
      $performanceBuild = Get-MIRAssuranceCommitCandidateIdentity -Commit $performanceCommit
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
      $checks.performance_source_candidate=(
        [long]$performanceBuild.bytes -eq [long]$candidateIdentity.bytes -and
        [int]$performanceBuild.entries -eq [int]$candidateIdentity.entries -and
        [string]$performanceBuild.sha256 -eq [string]$candidateIdentity.sha256 -and
        [string]$performanceBuild.content_sha256 -eq [string]$candidateIdentity.content_sha256
      )
    }
  } catch {}
  $checks.target_profile_sha256=((Get-MIRAssuranceRepositoryFileHash -Path $targetsPath) -eq [string]$seal.target_profile_sha256)
  $checks.verification_profile_sha256=((Get-MIRAssuranceCanonicalJsonFileHash -Path (Get-MIRAssuranceVerificationProfilePath -Target $Context.target)) -eq [string]$seal.verification_profile_sha256)
  $checks.domain_policy_sha256=((Get-MIRAssuranceCanonicalJsonFileHash -Path $domainsPath) -eq [string]$seal.domain_policy_sha256)
  $checks.test_catalog_sha256=((Get-MIRAssuranceRepositoryFileHash -Path $catalogPath) -eq [string]$seal.test_catalog_sha256)
  $checks.validation_harness_sha256=((Get-MIRAssuranceTreeHash -Paths (Get-MIRAssuranceHarnessFiles)) -eq [string]$seal.validation_harness_sha256)
  $checks.trust_policy_sha256=((Get-MIRAssuranceCanonicalJsonFileHash -Path (Get-MIRAssuranceCanonicalTrustPolicyPath)) -eq [string]$seal.trust_policy_sha256)
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
          [string]$performance.candidate.source_commit -eq [string]$seal.performance_source_commit
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
          [string]$manualReview.source_commit -eq [string]$seal.package_source_commit -and
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
