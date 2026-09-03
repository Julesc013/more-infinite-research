function Get-MIR4CustodySealInputsV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][string]$ExactEngineEvidenceBundlePath,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$QualificationRecordPath,
    [Parameter(Mandatory)][string]$ReviewRecordPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CandidatePath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExactEngineTrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$EvidenceVerificationScratchRoot,
    [string]$SchemaRoot = ""
  )

  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemas = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $null = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $QualificationRecordPath -Label "Offline qualification record"
  $null = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ReviewRecordPath -Label "Offline review record"
  $admission = Get-MIR4CustodyAdmissionV1 -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -CandidatePlanPath $CandidatePlanPath -CandidatePath $CandidatePath -SchemaRoot $schemas
  $exactEngineEvidence = Assert-MIR4ExactEngineQualificationEvidenceBundleV1 -RepoRoot $repo `
    -EvidenceBundlePath $ExactEngineEvidenceBundlePath -CandidateManifestPath $CandidateManifestPath `
    -CandidatePlanPath $CandidatePlanPath -Admission $admission `
    -ExactEngineExecutablePath $ExactEngineExecutablePath -SshKeygenPath $SshKeygenPath `
    -TrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
    -ScratchRoot $EvidenceVerificationScratchRoot -SchemaRoot $schemas
  $qualification = Assert-MIR4BootstrapRecordFileV1 -Path $QualificationRecordPath `
    -SchemaPath (Join-Path $schemas "mir4-offline-qualification-record.schema.json")
  $review = Assert-MIR4BootstrapRecordFileV1 -Path $ReviewRecordPath `
    -SchemaPath (Join-Path $schemas "mir4-offline-review-record.schema.json")

  $manifestBinding = New-MIR4CustodyRecordBindingV1 -Role "candidate-manifest" `
    -Record $admission.manifest -Path $CandidateManifestPath
  $planBinding = New-MIR4CustodyRecordBindingV1 -Role "candidate-plan" `
    -Record $admission.plan -Path $CandidatePlanPath
  $exactEngineEvidenceBinding = New-MIR4CustodyRecordBindingV1 -Role "exact-engine-evidence" `
    -Record $exactEngineEvidence -Path $ExactEngineEvidenceBundlePath
  $qualificationBinding = New-MIR4CustodyRecordBindingV1 -Role "qualification" `
    -Record $qualification -Path $QualificationRecordPath
  $reviewBinding = New-MIR4CustodyRecordBindingV1 -Role "review" -Record $review -Path $ReviewRecordPath

  if ([string]$qualification.status -cne "passed" -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $qualification.candidate_manifest) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifestBinding) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $qualification.candidate_plan) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $planBinding) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $qualification.exact_engine_evidence) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $exactEngineEvidenceBinding) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $qualification.candidate) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $exactEngineEvidence.payload.candidate) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $qualification.engine) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $exactEngineEvidence.payload.engine) -or
      [string]$qualification.proof_root_sha256 -cne [string]$exactEngineEvidence.record_sha256 -or
      [string]$qualification.candidate.target_id -cne [string]$admission.target.target_id -or
      [string]$qualification.candidate.distribution_version -cne [string]$admission.projection.distribution_version -or
      [string]$qualification.candidate.archive_name -cne [string]$admission.archive_name -or
      [string]$qualification.candidate.archive_sha256 -cne [string]$admission.manifest.local_distribution.archive_sha256 -or
      [long]$qualification.candidate.bytes -ne [long]$admission.manifest.local_distribution.bytes -or
      [string]$qualification.engine.version -cne [string]$admission.target.engine_lock.version -or
      [string]$qualification.engine.executable_sha256 -cne [string]$admission.target.engine_lock.executable_sha256) {
    throw "The passed qualification does not bind the admitted f210 manifest, plan, candidate, and exact engine lock."
  }
  if ([string]$review.status -cne "passed" -or [string]$review.review_class -cne "human-manual" -or
      [string]$review.decision -cne "accepted-local-proof-only" -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $review.candidate_manifest) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifestBinding) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $review.candidate_plan) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $planBinding) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $review.qualification) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $qualificationBinding)) {
    throw "The passed human review does not bind the admitted f210 manifest, plan, and qualification."
  }

  return [pscustomobject][ordered]@{
    admission = $admission
    exact_engine_evidence = $exactEngineEvidence
    qualification = $qualification
    review = $review
    bound_records = @($manifestBinding, $planBinding, $exactEngineEvidenceBinding, $qualificationBinding, $reviewBinding)
  }
}

function Assert-MIR4OfflineCustodyModeV1 {
  param(
    [Parameter(Mandatory)][string]$Mode,
    [Parameter(Mandatory)][string]$Allowed
  )

  if ($Mode -cne $Allowed) {
    throw "MIR 4 offline candidate custody rejects mode '$Mode'; only '$Allowed' is admitted."
  }
}

function Test-MIR4CustodyDescendantPathV1 {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Path
  )

  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $pathFull = [IO.Path]::GetFullPath($Path)
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  return $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, $comparison)
}

function Assert-MIR4UntrackedCustodyPathV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Label
  )

  if (-not [IO.Path]::IsPathRooted($Path)) { throw "$Label requires an explicit absolute path." }
  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $full = [IO.Path]::GetFullPath($Path)
  $allowedRoots = @((Join-Path $repo "build"), (Join-Path $repo ".mir/local"))
  if (@($allowedRoots | Where-Object { Test-MIR4CustodyDescendantPathV1 -Root $_ -Path $full }).Count -eq 0) {
    throw "$Label must remain below build/ or .mir/local/: $full"
  }
  $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $full
  & git -C $repo check-ignore --quiet -- $full
  if ($LASTEXITCODE -ne 0) { throw "$Label must be explicitly git-ignored: $full" }
  return $full
}

function Assert-MIR4ExplicitExecutableV1 {
  param([Parameter(Mandatory)][string]$Path)

  if (-not [IO.Path]::IsPathRooted($Path)) { throw "OpenSSH ssh-keygen requires an explicit absolute executable path." }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "OpenSSH ssh-keygen is missing: $Path" }
  return (Resolve-Path -LiteralPath $Path).Path
}
