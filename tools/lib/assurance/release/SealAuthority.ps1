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

function Get-MIRAssurancePerformanceEvidenceArtifact {
  param([Parameter(Mandatory)]$Bundle)

  $capsules = @($Bundle.evidence | Where-Object { [string]$_.test_id -eq "runtime.performance-regression" })
  if ($capsules.Count -ne 1 -or [string]$capsules[0].status -ne "passed") {
    throw "The evidence bundle must contain exactly one passing runtime.performance-regression capsule."
  }
  $artifacts = @($capsules[0].artifacts | Where-Object { [string]$_.kind -eq "runtime-performance-evidence" })
  if ($artifacts.Count -ne 1) {
    throw "The performance capsule must contain exactly one captured runtime-performance-evidence artifact."
  }
  $artifact = $artifacts[0]
  $artifactPath = Resolve-MIRAssurancePath -Path ([string]$artifact.path)
  if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
    throw "Captured runtime performance evidence is absent: $artifactPath"
  }
  $item = Get-Item -LiteralPath $artifactPath
  if ([long]$artifact.bytes -ne [long]$item.Length -or
      [string]$artifact.sha256 -ne (Get-MIRAssuranceSha256 -Path $artifactPath)) {
    throw "Captured runtime performance evidence no longer matches its capsule descriptor."
  }
  return $artifact
}
