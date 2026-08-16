# R0 proof-only custody. This library never grants publication authority and all
# key material and generated evidence must remain below ignored local roots.
$bootstrapMaterialization = Join-Path $PSScriptRoot "BootstrapMaterialization.ps1"
if (-not (Test-Path -LiteralPath $bootstrapMaterialization -PathType Leaf)) {
  throw "The MIR 4 bootstrap record authority is missing: $bootstrapMaterialization"
}
. $bootstrapMaterialization

$distributionIdentityAuthority = Join-Path $PSScriptRoot "../validation/MIR4DistributionIdentity.ps1"
if (-not (Test-Path -LiteralPath $distributionIdentityAuthority -PathType Leaf)) {
  throw "The MIR 4 distribution identity authority is missing: $distributionIdentityAuthority"
}
. $distributionIdentityAuthority

$script:MIR4BootstrapCanonicalizationV1 = "MIR4BootstrapCanonicalJsonV1"
$script:MIR4OfflineSealNamespaceV1 = "mir4-offline-candidate-seal-v1"
$script:MIR4ExactEngineEvidenceNamespaceV1 = "mir4-exact-engine-qualification-v1"
$script:MIR4ExactEngineObservationIdsV1 = @(
  "clean-install",
  "direct-upgrade-from-3.2.10",
  "reload-after-upgrade-1",
  "reload-after-upgrade-2",
  "settings-profile-state-preservation",
  "target-compatibility"
)

function Get-MIR4CustodyRepoRootV1 {
  param([string]$RepoRoot = "")

  if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Join-Path $PSScriptRoot "../../.."
  }
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4CustodySchemaRootV1 {
  param(
    [string]$RepoRoot = "",
    [string]$SchemaRoot = ""
  )

  if (-not [string]::IsNullOrWhiteSpace($SchemaRoot)) {
    return (Resolve-Path -LiteralPath $SchemaRoot).Path
  }
  return Join-Path (Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot) "spec/schemas"
}

function Write-MIR4CustodyRecordV1 {
  param(
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$Path
  )

  if ([string]$Record.canonicalization -cne $script:MIR4BootstrapCanonicalizationV1) {
    throw "MIR 4 custody records must declare $($script:MIR4BootstrapCanonicalizationV1)."
  }
  if (Test-Path -LiteralPath $Path) {
    throw "MIR 4 custody records are immutable and cannot overwrite an existing path: $Path"
  }
  $null = Write-MIR4BootstrapRecord -Record $Record -Path $Path
  return Assert-MIR4BootstrapRecordFileV1 -Path $Path
}

function Assert-MIR4BootstrapRecordFileV1 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$SchemaPath = ""
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "MIR 4 custody record is missing: $Path"
  }
  $bytes = [IO.File]::ReadAllBytes($Path)
  $decoder = [Text.UTF8Encoding]::new($false, $true)
  try { $text = $decoder.GetString($bytes) } catch { throw "MIR 4 custody record is not strict UTF-8: $Path" }
  if ($text.StartsWith([char]0xFEFF)) { throw "MIR 4 custody records must not contain a UTF-8 BOM: $Path" }
  try { $record = $text | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw "MIR 4 custody record is invalid JSON: $Path" }
  if (-not (Test-MIR4BootstrapRecordHash -Record $record)) {
    throw "MIR 4 custody record hash is invalid: $Path"
  }
  $canonicalText = (ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + "`n"
  if ($text -cne $canonicalText) {
    throw "MIR 4 custody record bytes are not canonical $($script:MIR4BootstrapCanonicalizationV1): $Path"
  }
  if (-not [string]::IsNullOrWhiteSpace($SchemaPath)) {
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) { throw "MIR 4 custody schema is missing: $SchemaPath" }
    if (-not ($text | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) {
      throw "MIR 4 custody record does not satisfy its strict schema: $Path"
    }
  }
  return $record
}

function Assert-MIR4GovernedBootstrapRecordFileV1 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$SchemaPath
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "MIR 4 governed record is missing: $Path" }
  if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) { throw "MIR 4 governed schema is missing: $SchemaPath" }
  $bytes = [IO.File]::ReadAllBytes($Path)
  $decoder = [Text.UTF8Encoding]::new($false, $true)
  try { $text = $decoder.GetString($bytes) } catch { throw "MIR 4 governed record is not strict UTF-8: $Path" }
  if ($text.StartsWith([char]0xFEFF)) { throw "MIR 4 governed records must not contain a UTF-8 BOM: $Path" }
  try { $record = $text | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw "MIR 4 governed record is invalid JSON: $Path" }
  if (-not (Test-MIR4BootstrapRecordHash -Record $record)) { throw "MIR 4 governed record hash is invalid: $Path" }
  if (-not ($text | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) {
    throw "MIR 4 governed record does not satisfy its strict schema: $Path"
  }
  return $record
}

function Assert-MIR4CheckedRootSetFileV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$SchemaPath
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "MIR 4 bootstrap root set is missing: $Path" }
  if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) { throw "MIR 4 bootstrap root-set schema is missing: $SchemaPath" }
  $before = Get-MIR4Sha256File -Path $Path
  $checker = Join-Path $RepoRoot "tools/commands/release/New-MIR4BootstrapRootSet.ps1"
  $null = & $checker -RepoRoot $RepoRoot -OutputPath $Path -Check
  $after = Get-MIR4Sha256File -Path $Path
  if ($before -cne $after) { throw "MIR 4 bootstrap root set changed while custody verified it." }
  $bytes = [IO.File]::ReadAllBytes($Path)
  $decoder = [Text.UTF8Encoding]::new($false, $true)
  try { $text = $decoder.GetString($bytes) } catch { throw "MIR 4 bootstrap root set is not strict UTF-8: $Path" }
  if ($text.StartsWith([char]0xFEFF)) { throw "MIR 4 bootstrap root set must not contain a UTF-8 BOM: $Path" }
  if (-not ($text | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) {
    throw "MIR 4 bootstrap root set does not satisfy its strict schema: $Path"
  }
  return $text | ConvertFrom-Json -Depth 100 -DateKind String
}

function New-MIR4CustodyRecordBindingV1 {
  param(
    [Parameter(Mandatory)][string]$Role,
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$Path
  )

  return [pscustomobject][ordered]@{
    role = $Role
    kind = [string]$Record.kind
    record_sha256 = [string]$Record.record_sha256
    file_sha256 = Get-MIR4Sha256File -Path $Path
  }
}

function Get-MIR4CustodyAdmissionV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CandidatePath,
    [string]$SchemaRoot = ""
  )

  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemas = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $expectedPlanPath = (Resolve-Path -LiteralPath (Join-Path $repo ".mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV1.json")).Path
  if ((Resolve-Path -LiteralPath $CandidatePlanPath).Path -cne $expectedPlanPath) {
    throw "Offline custody requires the exact current tracked bootstrap plan path."
  }
  $plan = Assert-MIR4GovernedBootstrapRecordFileV1 -Path $CandidatePlanPath `
    -SchemaPath (Join-Path $schemas "mir4-bootstrap-local-candidate-plan.schema.json")
  $governedRoot = [IO.Path]::GetFullPath((Join-Path $repo ([string]$plan.package_policy.output_root)))
  $expectedManifestPath = [IO.Path]::GetFullPath((Join-Path $governedRoot "manifests/f210.json"))
  $expectedCandidatePath = [IO.Path]::GetFullPath((Join-Path $governedRoot "distributions/more-infinite-research_4.0.21000.zip"))
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if (-not [string]::Equals([IO.Path]::GetFullPath($CandidateManifestPath), $expectedManifestPath, $comparison) -or
      [string]::IsNullOrWhiteSpace($CandidatePath) -or
      -not [string]::Equals([IO.Path]::GetFullPath($CandidatePath), $expectedCandidatePath, $comparison)) {
    throw "Offline custody accepts only the exact governed f210 manifest and distribution paths below the plan output root."
  }
  $manifestPath = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $expectedManifestPath -Label "Local candidate manifest"
  $candidate = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $expectedCandidatePath -Label "Local candidate archive"
  $manifest = Assert-MIR4BootstrapRecordFileV1 -Path $manifestPath `
    -SchemaPath (Join-Path $schemas "mir4-bootstrap-local-candidate-manifest.schema.json")
  $checker = Join-Path $repo "tools/commands/release/New-MIR4BootstrapLocalCandidate.ps1"
  $null = & $checker -RepoRoot $repo -PlanPath $CandidatePlanPath -Target f210 -OutputRoot $governedRoot -Check

  if ([string]$manifest.target_key -cne "f210" -or [string]$manifest.factorio_line -cne "2.1" -or
      [string]$manifest.distribution_version -cne "4.0.21000" -or
      [string]$manifest.admission -cne "admitted-local-emergency-lane" -or
      [bool]$manifest.public_output_authorized) {
    throw "Offline candidate custody admits only the unpublished f210 emergency-lane manifest."
  }
  if ([string]$plan.source_version -cne "4.0.0" -or [bool]$plan.public_output_authorized) {
    throw "Offline candidate custody requires the current unpublished MIR 4.0.0 bootstrap plan."
  }
  $targetRows = @($plan.targets | Where-Object { [string]$_.target_key -ceq "f210" })
  if ($targetRows.Count -ne 1) { throw "The current bootstrap plan does not contain exactly one f210 admission." }
  $target = $targetRows[0]
  if ([string]$target.target_id -cne "factorio-2.1" -or
      [string]$target.distribution_target_code -cne "210" -or
      [string]$target.distribution_version -cne "4.0.21000" -or
      [string]$target.admission -cne "admitted-local-emergency-lane") {
    throw "The current bootstrap plan does not admit the exact f210 distribution identity."
  }
  $correctionPath = Join-Path $repo ([string]$target.correction_authority.path)
  $correction = Assert-MIR4BootstrapRecordFileV1 -Path $correctionPath `
    -SchemaPath (Join-Path $schemas 'mir4-approved-bootstrap-correction-delta.schema.json')
  if ([string]$correction.record_sha256 -cne [string]$target.correction_authority.record_sha256 -or
      [string]$manifest.correction_authority.record_sha256 -cne [string]$correction.record_sha256 -or
      [string]$correction.finding -cne 'MIR3-TERM-0033' -or
      [string]$correction.target_key -cne 'f210') {
    throw 'Offline candidate custody requires the exact approved MIR3-TERM-0033 correction binding.'
  }
  $rootSetPath = Join-Path $repo ".mir/releases/waves/mir4-r0/bootstrap-root-set.json"
  $rootSet = Assert-MIR4CheckedRootSetFileV1 -RepoRoot $repo -Path $rootSetPath `
    -SchemaPath (Join-Path $schemas "mir4-bootstrap-root-set.schema.json")
  $rootRows = @($rootSet.targets | Where-Object { [string]$_.target_id -ceq "f210" })
  if ($rootRows.Count -ne 1) { throw "The current bootstrap root set does not contain exactly one f210 row." }
  $rootRow = $rootRows[0]

  $registryPath = Join-Path $repo $script:MIR4TargetRegistryV2Path
  $versionAuthorityPath = Join-Path $repo $script:MIR4VersionAuthorityV2Path
  $null = Assert-MIR4R0DistributionIdentity -RepoRoot $repo
  $registry = Import-MIR4IdentityJson -RepoRoot $repo -RelativePath $script:MIR4TargetRegistryV2Path
  $versionAuthority = Import-MIR4IdentityJson -RepoRoot $repo -RelativePath $script:MIR4VersionAuthorityV2Path
  $projection = Resolve-MIR4DistributionIdentity -TargetRegistry $registry -VersionAuthority $versionAuthority `
    -TargetId ([string]$target.target_id) -SourceMinor 0 -SourcePatch 0
  if ([string]$projection.distribution_target_code -cne "210" -or
      [string]$projection.source_version -cne [string]$plan.source_version -or
      [string]$projection.distribution_version -cne [string]$manifest.distribution_version) {
    throw "The f210 manifest and plan do not match the current V2 distribution identity resolver."
  }

  $archiveName = [IO.Path]::GetFileName([string]$manifest.local_distribution.path)
  if ($archiveName -cne [string]$projection.package_name) {
    throw "The admitted manifest archive name does not match the current V2 distribution identity."
  }
  $candidate = (Resolve-Path -LiteralPath $candidate).Path
  $inventory = Get-MIR4ArchiveInventory -Path $candidate
  $expectedRoot = "more-infinite-research_$($projection.distribution_version)"
  if ([IO.Path]::GetFileName($candidate) -cne $archiveName -or [string]$inventory.root -cne $expectedRoot -or
      [string]$inventory.archive_sha256 -cne [string]$manifest.local_distribution.archive_sha256 -or
      [string]$inventory.content_sha256 -cne [string]$manifest.local_distribution.content_sha256 -or
      [long]$inventory.bytes -ne [long]$manifest.local_distribution.bytes -or
      [long]$inventory.entry_count -ne [long]$manifest.local_distribution.entry_count) {
    throw "The candidate archive inventory and exact package root do not match the admitted self-hashed manifest."
  }
  $predecessorPath = Join-Path $repo ([string]$target.predecessor.archive_path)
  if ((Get-MIR4Sha256File -Path $predecessorPath) -cne [string]$target.predecessor.archive_sha256) {
    throw "The admitted plan predecessor archive does not match its exact bound identity."
  }
  $equivalence = Compare-MIR4BootstrapCorrectedCandidate -CandidatePath $candidate -PredecessorPath $predecessorPath `
    -ExpectedCandidateRoot $expectedRoot -ExpectedPredecessorRoot "more-infinite-research_$($target.predecessor.release)" `
    -ExpectedCandidateVersion ([string]$projection.distribution_version) `
    -ExpectedPredecessorVersion ([string]$target.predecessor.release) -Correction $correction -ThrowOnDifference
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $equivalence) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.equivalence)) {
    throw "The admitted manifest equivalence record does not equal a fresh predecessor comparison."
  }

  $authorities = [pscustomobject][ordered]@{
    target_registry = [pscustomobject][ordered]@{
      kind = [string]$registry.kind
      status = [string]$registry.status
      path = $script:MIR4TargetRegistryV2Path
      file_sha256 = Get-MIR4Sha256File -Path $registryPath
    }
    version_authority = [pscustomobject][ordered]@{
      kind = [string]$versionAuthority.kind
      status = [string]$versionAuthority.status
      path = $script:MIR4VersionAuthorityV2Path
      file_sha256 = Get-MIR4Sha256File -Path $versionAuthorityPath
    }
  }
  return [pscustomobject][ordered]@{
    manifest = $manifest
    plan = $plan
    target = $target
    projection = $projection
    identity_authorities = $authorities
    archive_name = $archiveName
  }
}

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

function Invoke-MIR4OpenSshProcessV1 {
  param(
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Arguments,
    [string]$InputPath = ""
  )

  $executable = Assert-MIR4ExplicitExecutableV1 -Path $SshKeygenPath
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $executable
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.RedirectStandardInput = -not [string]::IsNullOrWhiteSpace($InputPath)
  if ($startInfo.RedirectStandardInput -and -not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "OpenSSH verification input is missing: $InputPath"
  }
  foreach ($argument in $Arguments) { $null = $startInfo.ArgumentList.Add([string]$argument) }

  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  try {
    if (-not $process.Start()) { throw "Unable to start OpenSSH ssh-keygen." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if ($startInfo.RedirectStandardInput) {
      $input = [IO.File]::OpenRead($InputPath)
      try {
        $input.CopyTo($process.StandardInput.BaseStream)
        $process.StandardInput.BaseStream.Flush()
      } finally {
        $input.Dispose()
        $process.StandardInput.Close()
      }
    }
    $process.WaitForExit()
    return [pscustomobject][ordered]@{
      exit_code = [int]$process.ExitCode
      stdout = [string]$stdoutTask.GetAwaiter().GetResult()
      stderr = [string]$stderrTask.GetAwaiter().GetResult()
    }
  } finally {
    $process.Dispose()
  }
}

function Get-MIR4OpenSshPublicKeyLineV1 {
  param([Parameter(Mandatory)][string]$PublicKeyPath)

  if (-not [IO.Path]::IsPathRooted($PublicKeyPath)) { throw "The Ed25519 public key requires an explicit absolute path." }
  if (-not (Test-Path -LiteralPath $PublicKeyPath -PathType Leaf)) { throw "Ed25519 public key is missing: $PublicKeyPath" }
  $lines = @([IO.File]::ReadAllLines($PublicKeyPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($lines.Count -ne 1 -or $lines[0] -notmatch '^ssh-ed25519 [A-Za-z0-9+/]+={0,3}(?: [^\r\n]+)?$') {
    throw "The proof-only public key must contain one OpenSSH Ed25519 key."
  }
  return ([string]$lines[0]).Trim()
}

function Get-MIR4OpenSshPublicKeyFingerprintV1 {
  param(
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$PublicKeyPath
  )

  $result = Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $SshKeygenPath -Arguments @("-lf", $PublicKeyPath, "-E", "sha256")
  if ($result.exit_code -ne 0 -or $result.stdout -notmatch 'SHA256:[A-Za-z0-9+/]+') {
    throw "OpenSSH could not fingerprint the proof-only Ed25519 public key."
  }
  return [string]$Matches[0]
}

function New-MIR4ProofOnlyEd25519KeyPairV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$PrivateKeyPath,
    [Parameter(Mandatory)][string]$PublicKeyPath,
    [Parameter(Mandatory)][string]$Identity,
    [string]$Mode = "proof-only"
  )

  Assert-MIR4OfflineCustodyModeV1 -Mode $Mode -Allowed "proof-only"
  if ($Identity -notmatch '^[A-Za-z0-9][A-Za-z0-9._@+-]{0,127}$') { throw "Invalid proof-only signing identity." }
  $private = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $RepoRoot -Path $PrivateKeyPath -Label "Proof-only private key"
  $public = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $RepoRoot -Path $PublicKeyPath -Label "Proof-only public key"
  if ($public -cne "$private.pub") { throw "The explicit public key path must be the private key path plus '.pub'." }
  if ((Test-Path -LiteralPath $private) -or (Test-Path -LiteralPath $public)) {
    throw "Proof-only signing keys already exist; custody never overwrites keys."
  }
  $parent = Split-Path -Parent $private
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $result = Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $SshKeygenPath -Arguments @(
    "-q", "-t", "ed25519", "-N", "", "-C", $Identity, "-f", $private
  )
  if ($result.exit_code -ne 0 -or -not (Test-Path -LiteralPath $private -PathType Leaf) -or
      -not (Test-Path -LiteralPath $public -PathType Leaf)) {
    throw "OpenSSH failed to create the proof-only Ed25519 key pair."
  }
  return [pscustomobject][ordered]@{
    kind = "MIR4SigningProviderV1"
    algorithm = "ssh-ed25519"
    signature_format = "sshsig"
    public_key = Get-MIR4OpenSshPublicKeyLineV1 -PublicKeyPath $public
    public_key_fingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $public
    private_key_committed = $false
  }
}

function Test-MIR4OpenSshSignatureV1 {
  param(
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$PublicKeyPath,
    [Parameter(Mandatory)][string]$Identity,
    [Parameter(Mandatory)][string]$Namespace,
    [Parameter(Mandatory)][string]$PayloadPath,
    [Parameter(Mandatory)][string]$SignaturePath,
    [Parameter(Mandatory)][string]$ScratchRoot
  )

  if ($Identity -notmatch '^[A-Za-z0-9][A-Za-z0-9._@+-]{0,127}$' -or
      $Namespace -notmatch '^[a-z0-9][a-z0-9._-]{0,63}$') { return $false }
  try {
    $publicKey = Get-MIR4OpenSshPublicKeyLineV1 -PublicKeyPath $PublicKeyPath
    if (-not (Test-Path -LiteralPath $PayloadPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $SignaturePath -PathType Leaf)) { return $false }
    if (-not (Test-Path -LiteralPath $ScratchRoot -PathType Container)) {
      New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null
    }
    $allowedSigners = Join-Path $ScratchRoot "allowed-signers"
    [IO.File]::WriteAllText(
      $allowedSigners,
      "$Identity namespaces=`"$Namespace`" $publicKey`n",
      [Text.UTF8Encoding]::new($false)
    )
    $result = Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $SshKeygenPath -Arguments @(
      "-Y", "verify", "-f", $allowedSigners, "-I", $Identity,
      "-n", $Namespace, "-s", $SignaturePath
    ) -InputPath $PayloadPath
    return $result.exit_code -eq 0
  } catch {
    return $false
  }
}

function Assert-MIR4ExactEngineQualificationEvidenceBundleV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$EvidenceBundlePath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)]$Admission,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [string]$SchemaRoot = ""
  )

  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemas = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $bundlePath = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $EvidenceBundlePath `
    -Label "Exact-engine qualification evidence bundle"
  $scratch = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ScratchRoot `
    -Label "Exact-engine evidence verification scratch root"
  if (-not [IO.Path]::IsPathRooted($ExactEngineExecutablePath) -or
      -not (Test-Path -LiteralPath $ExactEngineExecutablePath -PathType Leaf)) {
    throw "Exact-engine qualification requires an explicit existing engine executable path."
  }
  $engineExecutable = (Resolve-Path -LiteralPath $ExactEngineExecutablePath).Path
  $evidence = Assert-MIR4BootstrapRecordFileV1 -Path $bundlePath `
    -SchemaPath (Join-Path $schemas "mir4-exact-engine-qualification-evidence-bundle.schema.json")
  if (-not (Test-MIR4BootstrapRecordHash -Record $evidence.payload) -or
      [string]$evidence.payload.record_sha256 -cne [string]$evidence.signature.payload_record_sha256 -or
      [string]$evidence.payload.producer.identity -cne [string]$evidence.signature.identity -or
      [string]$evidence.payload.producer.namespace -cne [string]$evidence.signature.namespace) {
    throw "Exact-engine qualification evidence payload or signature binding is invalid."
  }

  $manifestBinding = New-MIR4CustodyRecordBindingV1 -Role "candidate-manifest" `
    -Record $Admission.manifest -Path $CandidateManifestPath
  $planBinding = New-MIR4CustodyRecordBindingV1 -Role "candidate-plan" `
    -Record $Admission.plan -Path $CandidatePlanPath
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $evidence.payload.candidate_manifest) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifestBinding) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $evidence.payload.candidate_plan) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $planBinding) -or
      [string]$evidence.payload.candidate.target_id -cne [string]$Admission.target.target_id -or
      [string]$evidence.payload.candidate.distribution_version -cne [string]$Admission.projection.distribution_version -or
      [string]$evidence.payload.candidate.archive_name -cne [string]$Admission.archive_name -or
      [string]$evidence.payload.candidate.archive_sha256 -cne [string]$Admission.manifest.local_distribution.archive_sha256 -or
      [long]$evidence.payload.candidate.bytes -ne [long]$Admission.manifest.local_distribution.bytes -or
      [string]$evidence.payload.engine.version -cne [string]$Admission.target.engine_lock.version -or
      [string]$evidence.payload.engine.executable_sha256 -cne [string]$Admission.target.engine_lock.executable_sha256 -or
      (Get-MIR4Sha256File -Path $engineExecutable) -cne [string]$Admission.target.engine_lock.executable_sha256 -or
      -not [bool]$evidence.payload.engine.network_denied) {
    throw "Exact-engine qualification evidence does not bind the admitted f210 candidate, plan, and engine executable."
  }

  $observations = @($evidence.payload.observations)
  $observationIds = @($observations | ForEach-Object { [string]$_.id })
  if (($observationIds -join "|") -cne ($script:MIR4ExactEngineObservationIdsV1 -join "|") -or
      @($observations | Where-Object { [string]$_.status -cne "passed" }).Count -gt 0) {
    throw "Exact-engine qualification evidence must contain the exact ordered passed observation set."
  }
  $bundleRoot = Split-Path -Parent $bundlePath
  $pathComparer = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    [StringComparer]::OrdinalIgnoreCase
  } else { [StringComparer]::Ordinal }
  $artifactPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]$pathComparer)
  foreach ($observation in $observations) {
    $relative = [string]$observation.result_artifact.relative_path
    $nativeRelative = $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $artifactPath = [IO.Path]::GetFullPath((Join-Path $bundleRoot $nativeRelative))
    if (-not (Test-MIR4CustodyDescendantPathV1 -Root $bundleRoot -Path $artifactPath) -or
        -not $artifactPaths.Add($artifactPath)) {
      throw "Exact-engine observation artifacts must be distinct descendants of the evidence bundle directory."
    }
    $artifactPath = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $artifactPath `
      -Label "Exact-engine observation artifact"
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf) -or
        (Get-MIR4Sha256File -Path $artifactPath) -cne [string]$observation.result_artifact.sha256 -or
        [long](Get-Item -LiteralPath $artifactPath).Length -ne [long]$observation.result_artifact.bytes) {
      throw "Exact-engine observation artifact bytes do not match the signed evidence bundle: $relative"
    }
  }

  if (-not (Test-Path -LiteralPath $scratch -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
  }
  $workRoot = Join-Path $scratch ("exact-engine-verify-" + [guid]::NewGuid().ToString("N"))
  $null = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $workRoot `
    -Label "Exact-engine evidence verification work root"
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  try {
    $payloadPath = Join-Path $workRoot "payload.json"
    $null = Write-MIR4CustodyRecordV1 -Record $evidence.payload -Path $payloadPath
    $signatureBytes = [Convert]::FromBase64String([string]$evidence.signature.signature_base64)
    if ((Get-MIR4Sha256Bytes -Bytes $signatureBytes) -cne [string]$evidence.signature.signature_sha256) {
      throw "Exact-engine evidence signature bytes do not match their signed digest."
    }
    $signaturePath = Join-Path $workRoot "payload.json.sig"
    [IO.File]::WriteAllBytes($signaturePath, $signatureBytes)
    $embeddedPublicKeyPath = Join-Path $workRoot "embedded.pub"
    [IO.File]::WriteAllText(
      $embeddedPublicKeyPath,
      ([string]$evidence.payload.producer.public_key) + "`n",
      [Text.UTF8Encoding]::new($false)
    )
    $trustedFingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath `
      -PublicKeyPath $TrustedPublicKeyPath
    $embeddedFingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath `
      -PublicKeyPath $embeddedPublicKeyPath
    if ($trustedFingerprint -cne [string]$evidence.payload.producer.public_key_fingerprint -or
        $embeddedFingerprint -cne $trustedFingerprint -or
        -not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath `
          -PublicKeyPath $TrustedPublicKeyPath -Identity ([string]$evidence.signature.identity) `
          -Namespace $script:MIR4ExactEngineEvidenceNamespaceV1 -PayloadPath $payloadPath `
          -SignaturePath $signaturePath -ScratchRoot (Join-Path $workRoot "independent"))) {
      throw "Exact-engine qualification evidence is not signed by the explicit trusted producer key."
    }
    return $evidence
  } finally {
    if (Test-MIR4CustodyDescendantPathV1 -Root $scratch -Path $workRoot) {
      if (Test-Path -LiteralPath $workRoot -PathType Container) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
      }
    }
  }
}

function New-MIR4PublicationDryRunBundleV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][string]$ExactEngineEvidenceBundlePath,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$QualificationRecordPath,
    [Parameter(Mandatory)][string]$ReviewRecordPath,
    [Parameter(Mandatory)][string]$SealPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExactEngineTrustedPublicKeyPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [Parameter(Mandatory)][string]$CandidateId,
    [Parameter(Mandatory)][string]$TargetId,
    [Parameter(Mandatory)][string]$DistributionVersion,
    [Parameter(Mandatory)][string]$SourceVersion,
    [Parameter(Mandatory)][string]$SourceTag,
    [Parameter(Mandatory)][string]$DistributionTag,
    [Parameter(Mandatory)][string]$ReleaseTitle,
    [string[]]$Channels = @("github", "mod-portal"),
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$SchemaRoot = "",
    [string]$Mode = "dry-run"
  )

  Assert-MIR4OfflineCustodyModeV1 -Mode $Mode -Allowed "dry-run"
  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemaDirectory = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $output = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $OutputPath -Label "Publication dry-run bundle"
  $candidate = (Resolve-Path -LiteralPath $CandidatePath).Path
  if ($CandidateId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "Invalid MIR 4 candidate ID." }
  $inputs = Get-MIR4CustodySealInputsV1 -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
    -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
    -ReviewRecordPath $ReviewRecordPath -CandidatePath $candidate -SshKeygenPath $SshKeygenPath `
    -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
    -EvidenceVerificationScratchRoot (Join-Path $ScratchRoot "exact-engine-inputs") -SchemaRoot $schemaDirectory
  if (-not (Test-MIR4OfflineSealV1 -RepoRoot $repo -SealPath $SealPath -CandidatePath $candidate `
      -CandidateManifestPath $CandidateManifestPath `
      -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
      -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
      -ReviewRecordPath $ReviewRecordPath -SshKeygenPath $SshKeygenPath `
      -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
      -TrustedPublicKeyPath $TrustedPublicKeyPath -ScratchRoot $ScratchRoot -SchemaRoot $schemaDirectory)) {
    throw "Publication dry-run generation requires an explicitly trust-anchored offline seal."
  }
  $seal = Assert-MIR4BootstrapRecordFileV1 -Path $SealPath `
    -SchemaPath (Join-Path $schemaDirectory "mir4-offline-seal.schema.json")
  $projection = $inputs.admission.projection
  if ($CandidateId -cne [string]$seal.payload.candidate.candidate_id -or
      $TargetId -cne [string]$projection.target_id -or
      $DistributionVersion -cne [string]$projection.distribution_version -or
      $SourceVersion -cne [string]$projection.source_version -or
      $SourceTag -cne [string]$projection.source_tag -or
      $DistributionTag -cne [string]$projection.distribution_tag) {
    throw "Publication dry-run identity does not match the admitted current V2 f210 projection."
  }
  $channelSet = @($Channels | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  if ($channelSet.Count -eq 0 -or @($channelSet | Where-Object { $_ -notin @("github", "mod-portal") }).Count -gt 0) {
    throw "Publication dry-run channels must be github and/or mod-portal."
  }
  $archiveName = [IO.Path]::GetFileName($candidate)
  $archiveSha = Get-MIR4Sha256File -Path $candidate
  $archiveBytes = (Get-Item -LiteralPath $candidate).Length
  if ($archiveName -cne [string]$projection.package_name -or
      $archiveSha -cne [string]$seal.payload.candidate.archive_sha256 -or
      [long]$archiveBytes -ne [long]$seal.payload.candidate.bytes) {
    throw "Publication dry-run candidate bytes do not match the trust-anchored seal."
  }
  $channelRequests = @(
    foreach ($channel in $channelSet) {
      [pscustomobject][ordered]@{
        channel = $channel
        operation = "describe-request-only"
        asset_name = $archiveName
        expected_sha256 = $archiveSha
        mutation_allowed = $false
      }
    }
  )
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = "MIR4PublicationDryRunBundleV1"
    canonicalization = $script:MIR4BootstrapCanonicalizationV1
    mode = "dry-run"
    mutating = $false
    network_required = $false
    apply_allowed = $false
    publication_authority = $false
    seal = [pscustomobject][ordered]@{
      kind = [string]$seal.kind
      record_sha256 = [string]$seal.record_sha256
      file_sha256 = Get-MIR4Sha256File -Path $SealPath
    }
    source_identity = [pscustomobject][ordered]@{
      version = $SourceVersion
      proposed_tag = $SourceTag
    }
    distribution_identity = [pscustomobject][ordered]@{
      target_id = $TargetId
      version = $DistributionVersion
      proposed_tag = $DistributionTag
    }
    identity_authorities = $inputs.admission.identity_authorities
    candidate = [pscustomobject][ordered]@{
      candidate_id = $CandidateId
      target_id = $TargetId
      distribution_version = $DistributionVersion
      archive_name = $archiveName
      archive_sha256 = $archiveSha
      bytes = [long]$archiveBytes
    }
    release = [pscustomobject][ordered]@{
      title = $ReleaseTitle
      asset_name = $archiveName
      asset_sha256 = $archiveSha
    }
    channel_requests = $channelRequests
    rollback = [pscustomobject][ordered]@{
      partial_publication_policy = "not-applicable-no-mutation"
      mutation_count = 0
    }
    readback_verification = @(
      [pscustomobject][ordered]@{
        id = "candidate-sha256"
        operation = "sha256"
        subject = $archiveName
        expected = $archiveSha
      },
      [pscustomobject][ordered]@{
        id = "candidate-byte-count"
        operation = "byte-count"
        subject = $archiveName
        expected = [long]$archiveBytes
      }
    )
  }
  $written = Write-MIR4CustodyRecordV1 -Record $record -Path $output
  $schema = Join-Path $schemaDirectory "mir4-publication-dry-run-bundle.schema.json"
  $null = Assert-MIR4BootstrapRecordFileV1 -Path $output -SchemaPath $schema
  return $written
}

function Assert-MIR4PublicationDryRunForSealV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SealPath,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePath,
    [Parameter(Mandatory)]$Seal,
    [Parameter(Mandatory)]$Admission,
    [string]$SchemaRoot = ""
  )

  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemas = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $publication = Assert-MIR4BootstrapRecordFileV1 -Path $PublicationDryRunBundlePath `
    -SchemaPath (Join-Path $schemas "mir4-publication-dry-run-bundle.schema.json")
  if ([string]$publication.mode -cne "dry-run" -or $publication.mutating -or
      $publication.apply_allowed -or $publication.publication_authority -or
      [string]$publication.seal.record_sha256 -cne [string]$Seal.record_sha256 -or
      [string]$publication.seal.file_sha256 -cne (Get-MIR4Sha256File -Path $SealPath)) {
    throw "Publication dry-run does not bind the supplied non-mutating offline seal."
  }
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $publication.candidate) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $Seal.payload.candidate) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $publication.source_identity) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $Seal.payload.source_identity) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $publication.distribution_identity) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $Seal.payload.distribution_identity) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $publication.identity_authorities) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $Admission.identity_authorities)) {
    throw "Publication dry-run identity does not match the admitted sealed candidate."
  }
  $candidateName = [string]$Seal.payload.candidate.archive_name
  $candidateSha = [string]$Seal.payload.candidate.archive_sha256
  $candidateBytes = [long]$Seal.payload.candidate.bytes
  if ([string]$publication.release.asset_name -cne $candidateName -or
      [string]$publication.release.asset_sha256 -cne $candidateSha) {
    throw "Publication dry-run release identity does not bind the sealed candidate."
  }
  $channelNames = @($publication.channel_requests | ForEach-Object { [string]$_.channel })
  $sortedChannelNames = @($channelNames | Sort-Object -Unique)
  if (($channelNames -join "|") -cne ($sortedChannelNames -join "|") -or
      @($publication.channel_requests | Where-Object {
        [string]$_.asset_name -cne $candidateName -or [string]$_.expected_sha256 -cne $candidateSha -or [bool]$_.mutation_allowed
      }).Count -gt 0) {
    throw "Publication dry-run channel requests are not canonical candidate-bound descriptions."
  }
  $shaReadback = @($publication.readback_verification | Where-Object { [string]$_.id -ceq "candidate-sha256" })
  $byteReadback = @($publication.readback_verification | Where-Object { [string]$_.id -ceq "candidate-byte-count" })
  if ($shaReadback.Count -ne 1 -or $byteReadback.Count -ne 1 -or
      [string]$shaReadback[0].operation -cne "sha256" -or [string]$shaReadback[0].subject -cne $candidateName -or
      [string]$shaReadback[0].expected -cne $candidateSha -or [string]$byteReadback[0].operation -cne "byte-count" -or
      [string]$byteReadback[0].subject -cne $candidateName -or [long]$byteReadback[0].expected -ne $candidateBytes) {
    throw "Publication dry-run readback verification is incomplete or stale."
  }
  return $publication
}

function Assert-MIR4PublicationDryRunPairV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SealPath,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathA,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathB,
    [Parameter(Mandatory)]$Seal,
    [Parameter(Mandatory)]$Admission,
    [string]$SchemaRoot = ""
  )

  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemas = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $pathA = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $PublicationDryRunBundlePathA `
    -Label "Publication dry-run bundle A"
  $pathB = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $PublicationDryRunBundlePathB `
    -Label "Publication dry-run bundle B"
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if ([string]::Equals([IO.Path]::GetFullPath($pathA), [IO.Path]::GetFullPath($pathB), $comparison)) {
    throw "Publication dry-run idempotence requires two independently written bundle paths."
  }

  $runA = Assert-MIR4PublicationDryRunForSealV1 -RepoRoot $repo -SealPath $SealPath `
    -PublicationDryRunBundlePath $pathA -Seal $Seal -Admission $Admission -SchemaRoot $schemas
  $runB = Assert-MIR4PublicationDryRunForSealV1 -RepoRoot $repo -SealPath $SealPath `
    -PublicationDryRunBundlePath $pathB -Seal $Seal -Admission $Admission -SchemaRoot $schemas
  $canonicalA = ConvertTo-MIR4BootstrapCanonicalJson -Value $runA
  $canonicalB = ConvertTo-MIR4BootstrapCanonicalJson -Value $runB
  $fileShaA = Get-MIR4Sha256File -Path $pathA
  $fileShaB = Get-MIR4Sha256File -Path $pathB
  if ($canonicalA -cne $canonicalB -or
      [string]$runA.record_sha256 -cne [string]$runB.record_sha256 -or
      $fileShaA -cne $fileShaB) {
    throw "The independently written publication dry-run bundles are not canonically and byte-identical."
  }

  $bindings = @(
    [pscustomobject][ordered]@{
      run_id = "A"
      kind = [string]$runA.kind
      record_sha256 = [string]$runA.record_sha256
      file_sha256 = $fileShaA
    },
    [pscustomobject][ordered]@{
      run_id = "B"
      kind = [string]$runB.kind
      record_sha256 = [string]$runB.record_sha256
      file_sha256 = $fileShaB
    }
  )
  return [pscustomobject][ordered]@{
    records = @($runA, $runB)
    bindings = $bindings
  }
}

function New-MIR4OfflineSealV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][string]$ExactEngineEvidenceBundlePath,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$QualificationRecordPath,
    [Parameter(Mandatory)][string]$ReviewRecordPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExactEngineTrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$PrivateKeyPath,
    [Parameter(Mandatory)][string]$PublicKeyPath,
    [Parameter(Mandatory)][string]$Identity,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$SchemaRoot = "",
    [string]$Mode = "local-offline-proof"
  )

  Assert-MIR4OfflineCustodyModeV1 -Mode $Mode -Allowed "local-offline-proof"
  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemaDirectory = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $output = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $OutputPath -Label "Offline candidate seal"
  $scratch = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ScratchRoot -Label "Offline seal scratch root"
  $private = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $PrivateKeyPath -Label "Proof-only private key"
  $public = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $PublicKeyPath -Label "Proof-only public key"
  if (-not (Test-Path -LiteralPath $private -PathType Leaf)) { throw "Proof-only private key is missing." }
  $null = Get-MIR4OpenSshPublicKeyLineV1 -PublicKeyPath $public

  $sealSchema = Join-Path $schemaDirectory "mir4-offline-seal.schema.json"
  $inputs = Get-MIR4CustodySealInputsV1 -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
    -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
    -ReviewRecordPath $ReviewRecordPath -CandidatePath $CandidatePath -SshKeygenPath $SshKeygenPath `
    -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
    -EvidenceVerificationScratchRoot (Join-Path $scratch "exact-engine-inputs") -SchemaRoot $schemaDirectory
  $qualification = $inputs.qualification
  $candidate = (Resolve-Path -LiteralPath $CandidatePath).Path
  $candidateSha = Get-MIR4Sha256File -Path $candidate
  $candidateBytes = (Get-Item -LiteralPath $candidate).Length
  $candidateName = [IO.Path]::GetFileName($candidate)
  if ($candidateSha -cne [string]$qualification.candidate.archive_sha256 -or
      [long]$candidateBytes -ne [long]$qualification.candidate.bytes -or
      [string]$qualification.candidate.archive_name -cne $candidateName) {
    throw "Candidate and admitted passed qualification identities do not match."
  }

  $provider = [pscustomobject][ordered]@{
    kind = "MIR4SigningProviderV1"
    algorithm = "ssh-ed25519"
    signature_format = "sshsig"
    implementation = "OpenSSH-ssh-keygen"
    executable_sha256 = Get-MIR4Sha256File -Path (Assert-MIR4ExplicitExecutableV1 -Path $SshKeygenPath)
    public_key = Get-MIR4OpenSshPublicKeyLineV1 -PublicKeyPath $public
    public_key_fingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $public
    identity = $Identity
    namespace = $script:MIR4OfflineSealNamespaceV1
    scope = "proof-only-local-r0"
    private_key_committed = $false
  }
  $payload = [pscustomobject][ordered]@{
    schema = 1
    kind = "MIR4OfflineSealPayloadV1"
    canonicalization = $script:MIR4BootstrapCanonicalizationV1
    seal_scope = "local-offline-proof-only"
    publication_authority = $false
    candidate = [pscustomobject][ordered]@{
      candidate_id = [string]$qualification.candidate.candidate_id
      target_id = [string]$qualification.candidate.target_id
      distribution_version = [string]$qualification.candidate.distribution_version
      archive_name = [string]$qualification.candidate.archive_name
      archive_sha256 = $candidateSha
      bytes = [long]$candidateBytes
    }
    source_identity = [pscustomobject][ordered]@{
      version = [string]$inputs.admission.projection.source_version
      proposed_tag = [string]$inputs.admission.projection.source_tag
    }
    distribution_identity = [pscustomobject][ordered]@{
      target_id = [string]$inputs.admission.projection.target_id
      version = [string]$inputs.admission.projection.distribution_version
      proposed_tag = [string]$inputs.admission.projection.distribution_tag
    }
    identity_authorities = $inputs.admission.identity_authorities
    bound_records = @($inputs.bound_records)
    signing_provider = $provider
  }

  if (-not (Test-Path -LiteralPath $scratch -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
  }
  $workRoot = Join-Path $scratch ("seal-" + [guid]::NewGuid().ToString("N"))
  $null = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $workRoot -Label "Offline seal work root"
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  try {
    $payloadPath = Join-Path $workRoot "seal-payload.json"
    $payloadRecord = Write-MIR4CustodyRecordV1 -Record $payload -Path $payloadPath
    $signaturePath = "$payloadPath.sig"
    if (Test-Path -LiteralPath $signaturePath) { throw "Offline seal signature path is unexpectedly occupied." }
    $signResult = Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $SshKeygenPath -Arguments @(
      "-Y", "sign", "-f", $private, "-n", $script:MIR4OfflineSealNamespaceV1, $payloadPath
    )
    if ($signResult.exit_code -ne 0 -or -not (Test-Path -LiteralPath $signaturePath -PathType Leaf)) {
      throw "OpenSSH failed to sign the MIR 4 offline seal payload."
    }
    $verifyScratch = Join-Path $workRoot "independent-verification"
    if (-not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $public `
        -Identity $Identity -Namespace $script:MIR4OfflineSealNamespaceV1 -PayloadPath $payloadPath `
        -SignaturePath $signaturePath -ScratchRoot $verifyScratch)) {
      throw "Independent OpenSSH verification rejected the new MIR 4 offline seal signature."
    }
    $signatureBytes = [IO.File]::ReadAllBytes($signaturePath)
    $seal = [pscustomobject][ordered]@{
      schema = 1
      kind = "MIR4OfflineSealV1"
      canonicalization = $script:MIR4BootstrapCanonicalizationV1
      status = "sealed-local-proof-only"
      publication_authority = $false
      payload = $payloadRecord
      signature = [pscustomobject][ordered]@{
        algorithm = "ssh-ed25519"
        format = "sshsig"
        identity = $Identity
        namespace = $script:MIR4OfflineSealNamespaceV1
        payload_record_sha256 = [string]$payloadRecord.record_sha256
        signature_sha256 = Get-MIR4Sha256Bytes -Bytes $signatureBytes
        signature_base64 = [Convert]::ToBase64String($signatureBytes)
      }
    }
    $sealRecord = Write-MIR4CustodyRecordV1 -Record $seal -Path $output
    $null = Assert-MIR4BootstrapRecordFileV1 -Path $output -SchemaPath $sealSchema
    if (-not (Test-MIR4OfflineSealV1 -RepoRoot $repo -SealPath $output -CandidatePath $candidate `
        -CandidateManifestPath $CandidateManifestPath -CandidatePlanPath $CandidatePlanPath `
        -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
        -ExactEngineExecutablePath $ExactEngineExecutablePath `
        -QualificationRecordPath $QualificationRecordPath -ReviewRecordPath $ReviewRecordPath `
        -SshKeygenPath $SshKeygenPath -TrustedPublicKeyPath $public `
        -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
        -ScratchRoot (Join-Path $scratch "verify-new-seal") -SchemaRoot $schemaDirectory)) {
      throw "The completed MIR 4 offline seal failed independent verification."
    }
    return $sealRecord
  } finally {
    if (Test-MIR4CustodyDescendantPathV1 -Root $scratch -Path $workRoot) {
      if (Test-Path -LiteralPath $workRoot -PathType Container) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
      }
    }
  }
}

function Test-MIR4OfflineSealV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SealPath,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][string]$ExactEngineEvidenceBundlePath,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$QualificationRecordPath,
    [Parameter(Mandatory)][string]$ReviewRecordPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExactEngineTrustedPublicKeyPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [string]$SchemaRoot = ""
  )

  try {
    $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
    $schemaDirectory = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
    $scratch = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ScratchRoot -Label "Offline seal verification scratch root"
    $seal = Assert-MIR4BootstrapRecordFileV1 -Path $SealPath -SchemaPath (Join-Path $schemaDirectory "mir4-offline-seal.schema.json")
    $inputs = Get-MIR4CustodySealInputsV1 -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
      -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
      -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
      -ReviewRecordPath $ReviewRecordPath -CandidatePath $CandidatePath -SshKeygenPath $SshKeygenPath `
      -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
      -EvidenceVerificationScratchRoot (Join-Path $scratch "exact-engine-inputs") -SchemaRoot $schemaDirectory
    $expectedSource = [pscustomobject][ordered]@{
      version = [string]$inputs.admission.projection.source_version
      proposed_tag = [string]$inputs.admission.projection.source_tag
    }
    $expectedDistribution = [pscustomobject][ordered]@{
      target_id = [string]$inputs.admission.projection.target_id
      version = [string]$inputs.admission.projection.distribution_version
      proposed_tag = [string]$inputs.admission.projection.distribution_tag
    }
    if (-not (Test-MIR4BootstrapRecordHash -Record $seal.payload) -or
        [string]$seal.payload.record_sha256 -cne [string]$seal.signature.payload_record_sha256 -or
        [string]$seal.signature.identity -cne [string]$seal.payload.signing_provider.identity -or
        [string]$seal.signature.namespace -cne [string]$seal.payload.signing_provider.namespace -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $seal.payload.candidate) -cne
          (ConvertTo-MIR4BootstrapCanonicalJson -Value $inputs.qualification.candidate) -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $seal.payload.source_identity) -cne
          (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedSource) -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $seal.payload.distribution_identity) -cne
          (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedDistribution) -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $seal.payload.identity_authorities) -cne
          (ConvertTo-MIR4BootstrapCanonicalJson -Value $inputs.admission.identity_authorities) -or
        (ConvertTo-MIR4BootstrapCanonicalJson -Value @($seal.payload.bound_records)) -cne
          (ConvertTo-MIR4BootstrapCanonicalJson -Value @($inputs.bound_records))) { return $false }
    $signatureBytes = [Convert]::FromBase64String([string]$seal.signature.signature_base64)
    if ((Get-MIR4Sha256Bytes -Bytes $signatureBytes) -cne [string]$seal.signature.signature_sha256) { return $false }

    if (-not (Test-Path -LiteralPath $scratch -PathType Container)) {
      New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    }
    $workRoot = Join-Path $scratch ("verify-" + [guid]::NewGuid().ToString("N"))
    $null = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $workRoot -Label "Offline seal verification work root"
    New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
    try {
      $payloadPath = Join-Path $workRoot "payload.json"
      $null = Write-MIR4CustodyRecordV1 -Record $seal.payload -Path $payloadPath
      $signaturePath = Join-Path $workRoot "payload.json.sig"
      [IO.File]::WriteAllBytes($signaturePath, $signatureBytes)
      $embeddedPublicKeyPath = Join-Path $workRoot "embedded.pub"
      [IO.File]::WriteAllText(
        $embeddedPublicKeyPath,
        ([string]$seal.payload.signing_provider.public_key) + "`n",
        [Text.UTF8Encoding]::new($false)
      )
      $trustedFingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath `
        -PublicKeyPath $TrustedPublicKeyPath
      $embeddedFingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath `
        -PublicKeyPath $embeddedPublicKeyPath
      if ($trustedFingerprint -cne [string]$seal.payload.signing_provider.public_key_fingerprint -or
          $embeddedFingerprint -cne $trustedFingerprint) {
        return $false
      }
      return Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $TrustedPublicKeyPath `
        -Identity ([string]$seal.signature.identity) -Namespace ([string]$seal.signature.namespace) `
        -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $workRoot "independent")
    } finally {
      if (Test-MIR4CustodyDescendantPathV1 -Root $scratch -Path $workRoot) {
        if (Test-Path -LiteralPath $workRoot -PathType Container) {
          Remove-Item -LiteralPath $workRoot -Recurse -Force
        }
      }
    }
  } catch {
    return $false
  }
}

function Restore-MIR4OfflineCandidateV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SealPath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][string]$ExactEngineEvidenceBundlePath,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$QualificationRecordPath,
    [Parameter(Mandatory)][string]$ReviewRecordPath,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathA,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathB,
    [Parameter(Mandatory)][string]$SourceCandidatePath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExactEngineTrustedPublicKeyPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [string]$SchemaRoot = "",
    [string]$Mode = "restore"
  )

  Assert-MIR4OfflineCustodyModeV1 -Mode $Mode -Allowed "restore"
  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemaDirectory = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $output = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $OutputRoot -Label "Offline restoration output root"
  $receipt = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ReceiptPath -Label "Offline restoration receipt"
  $scratch = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $ScratchRoot -Label "Offline restoration verification scratch root"
  if (Test-MIR4CustodyDescendantPathV1 -Root $output -Path $receipt) {
    throw "The restoration receipt must be outside the verified clean restoration output."
  }
  if (-not (Test-MIR4OfflineSealV1 -RepoRoot $repo -SealPath $SealPath -CandidatePath $SourceCandidatePath `
      -CandidateManifestPath $CandidateManifestPath -CandidatePlanPath $CandidatePlanPath `
      -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
      -ExactEngineExecutablePath $ExactEngineExecutablePath `
      -QualificationRecordPath $QualificationRecordPath -ReviewRecordPath $ReviewRecordPath `
      -SshKeygenPath $SshKeygenPath -TrustedPublicKeyPath $TrustedPublicKeyPath `
      -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
      -ScratchRoot $scratch -SchemaRoot $schemaDirectory)) {
    throw "Candidate restoration requires a valid offline seal."
  }
  $seal = Assert-MIR4BootstrapRecordFileV1 -Path $SealPath -SchemaPath (Join-Path $schemaDirectory "mir4-offline-seal.schema.json")
  $inputs = Get-MIR4CustodySealInputsV1 -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
    -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
    -ReviewRecordPath $ReviewRecordPath -CandidatePath $SourceCandidatePath -SshKeygenPath $SshKeygenPath `
    -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
    -EvidenceVerificationScratchRoot (Join-Path $scratch "exact-engine-inputs") -SchemaRoot $schemaDirectory
  $publicationPair = Assert-MIR4PublicationDryRunPairV1 -RepoRoot $repo -SealPath $SealPath `
    -PublicationDryRunBundlePathA $PublicationDryRunBundlePathA `
    -PublicationDryRunBundlePathB $PublicationDryRunBundlePathB -Seal $seal `
    -Admission $inputs.admission -SchemaRoot $schemaDirectory
  $source = (Resolve-Path -LiteralPath $SourceCandidatePath).Path
  $sourceSha = Get-MIR4Sha256File -Path $source
  $sourceBytes = (Get-Item -LiteralPath $source).Length
  if ($sourceSha -cne [string]$seal.payload.candidate.archive_sha256 -or
      [long]$sourceBytes -ne [long]$seal.payload.candidate.bytes) {
    throw "Restoration source does not match the sealed candidate."
  }
  if (Test-Path -LiteralPath $output) {
    if (-not (Test-Path -LiteralPath $output -PathType Container)) { throw "Restoration output is not a directory." }
    if (@(Get-ChildItem -LiteralPath $output -Force).Count -ne 0) {
      throw "Restoration requires an existing empty directory or an absent output path."
    }
  } else {
    New-Item -ItemType Directory -Force -Path $output | Out-Null
  }
  $restoredPath = Join-Path $output ([string]$seal.payload.candidate.archive_name)
  [IO.File]::Copy($source, $restoredPath, $false)
  $restoredSha = Get-MIR4Sha256File -Path $restoredPath
  $restoredBytes = (Get-Item -LiteralPath $restoredPath).Length
  if ($restoredSha -cne $sourceSha -or [long]$restoredBytes -ne [long]$sourceBytes -or
      @(Get-ChildItem -LiteralPath $output -Recurse -File -Force).Count -ne 1) {
    throw "Restored candidate bytes or clean-output extent do not match the seal."
  }
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = "MIR4RestorationReceiptV1"
    canonicalization = $script:MIR4BootstrapCanonicalizationV1
    mode = "restore"
    status = "passed"
    publication_authority = $false
    output_was_empty = $true
    candidate = $seal.payload.candidate
    seal = [pscustomobject][ordered]@{
      kind = [string]$seal.kind
      record_sha256 = [string]$seal.record_sha256
      file_sha256 = Get-MIR4Sha256File -Path $SealPath
    }
    publication_dry_runs = @($publicationPair.bindings)
    source = [pscustomobject][ordered]@{
      archive_sha256 = $sourceSha
      bytes = [long]$sourceBytes
    }
    restored = [pscustomobject][ordered]@{
      archive_name = [IO.Path]::GetFileName($restoredPath)
      archive_sha256 = $restoredSha
      bytes = [long]$restoredBytes
    }
  }
  $written = Write-MIR4CustodyRecordV1 -Record $record -Path $receipt
  $null = Assert-MIR4BootstrapRecordFileV1 -Path $receipt -SchemaPath (Join-Path $schemaDirectory "mir4-restoration-receipt.schema.json")
  return $written
}

function New-MIR4EmergencyLaneCompletionRecordV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SealPath,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$CandidatePlanPath,
    [Parameter(Mandatory)][string]$ExactEngineEvidenceBundlePath,
    [Parameter(Mandatory)][string]$ExactEngineExecutablePath,
    [Parameter(Mandatory)][string]$QualificationRecordPath,
    [Parameter(Mandatory)][string]$ReviewRecordPath,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathA,
    [Parameter(Mandatory)][string]$PublicationDryRunBundlePathB,
    [Parameter(Mandatory)][string]$RestorationReceiptPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExactEngineTrustedPublicKeyPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TrustedPublicKeyPath,
    [Parameter(Mandatory)][string]$ScratchRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$SchemaRoot = "",
    [string]$Mode = "record"
  )

  Assert-MIR4OfflineCustodyModeV1 -Mode $Mode -Allowed "record"
  $repo = Get-MIR4CustodyRepoRootV1 -RepoRoot $RepoRoot
  $schemaDirectory = Get-MIR4CustodySchemaRootV1 -RepoRoot $repo -SchemaRoot $SchemaRoot
  $output = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $OutputPath -Label "Emergency-lane completion record"
  if (-not (Test-MIR4OfflineSealV1 -RepoRoot $repo -SealPath $SealPath -CandidatePath $CandidatePath `
      -CandidateManifestPath $CandidateManifestPath -CandidatePlanPath $CandidatePlanPath `
      -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
      -ExactEngineExecutablePath $ExactEngineExecutablePath `
      -QualificationRecordPath $QualificationRecordPath -ReviewRecordPath $ReviewRecordPath `
      -SshKeygenPath $SshKeygenPath -TrustedPublicKeyPath $TrustedPublicKeyPath `
      -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
      -ScratchRoot $ScratchRoot -SchemaRoot $schemaDirectory)) {
    throw "Emergency-lane completion requires a valid offline seal."
  }
  $seal = Assert-MIR4BootstrapRecordFileV1 -Path $SealPath -SchemaPath (Join-Path $schemaDirectory "mir4-offline-seal.schema.json")
  $inputs = Get-MIR4CustodySealInputsV1 -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -CandidatePlanPath $CandidatePlanPath -ExactEngineEvidenceBundlePath $ExactEngineEvidenceBundlePath `
    -ExactEngineExecutablePath $ExactEngineExecutablePath -QualificationRecordPath $QualificationRecordPath `
    -ReviewRecordPath $ReviewRecordPath -CandidatePath $CandidatePath -SshKeygenPath $SshKeygenPath `
    -ExactEngineTrustedPublicKeyPath $ExactEngineTrustedPublicKeyPath `
    -EvidenceVerificationScratchRoot (Join-Path $ScratchRoot "exact-engine-inputs") -SchemaRoot $schemaDirectory
  $publicationPair = Assert-MIR4PublicationDryRunPairV1 -RepoRoot $repo -SealPath $SealPath `
    -PublicationDryRunBundlePathA $PublicationDryRunBundlePathA `
    -PublicationDryRunBundlePathB $PublicationDryRunBundlePathB -Seal $seal `
    -Admission $inputs.admission -SchemaRoot $schemaDirectory
  $restoration = Assert-MIR4BootstrapRecordFileV1 -Path $RestorationReceiptPath `
    -SchemaPath (Join-Path $schemaDirectory "mir4-restoration-receipt.schema.json")
  $sealedCandidateJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $seal.payload.candidate
  $restoredCandidateJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $restoration.candidate
  $expectedDryRunsJson = ConvertTo-MIR4BootstrapCanonicalJson -Value @($publicationPair.bindings)
  $restoredDryRunsJson = ConvertTo-MIR4BootstrapCanonicalJson -Value @($restoration.publication_dry_runs)
  if ([string]$restoration.status -cne "passed" -or
      [string]$restoration.seal.record_sha256 -cne [string]$seal.record_sha256 -or
      [string]$restoration.seal.file_sha256 -cne (Get-MIR4Sha256File -Path $SealPath) -or
      $restoredDryRunsJson -cne $expectedDryRunsJson -or
      $restoredCandidateJson -cne $sealedCandidateJson -or
      [string]$restoration.source.archive_sha256 -cne [string]$seal.payload.candidate.archive_sha256 -or
      [long]$restoration.source.bytes -ne [long]$seal.payload.candidate.bytes -or
      [string]$restoration.restored.archive_name -cne [string]$seal.payload.candidate.archive_name -or
      [string]$restoration.restored.archive_sha256 -cne [string]$seal.payload.candidate.archive_sha256 -or
      [long]$restoration.restored.bytes -ne [long]$seal.payload.candidate.bytes) {
    throw "Restoration receipt does not bind the supplied offline seal and candidate."
  }
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = "MIR4EmergencyLaneCompletionRecordV1"
    canonicalization = $script:MIR4BootstrapCanonicalizationV1
    status = "passed-local-proof-only"
    publication_authority = $false
    candidate = $seal.payload.candidate
    seal = [pscustomobject][ordered]@{
      kind = [string]$seal.kind
      record_sha256 = [string]$seal.record_sha256
      file_sha256 = Get-MIR4Sha256File -Path $SealPath
    }
    publication_dry_runs = @($publicationPair.bindings)
    restoration = [pscustomobject][ordered]@{
      kind = [string]$restoration.kind
      record_sha256 = [string]$restoration.record_sha256
      file_sha256 = Get-MIR4Sha256File -Path $RestorationReceiptPath
    }
  }
  $written = Write-MIR4CustodyRecordV1 -Record $record -Path $output
  $null = Assert-MIR4BootstrapRecordFileV1 -Path $output `
    -SchemaPath (Join-Path $schemaDirectory "mir4-emergency-lane-completion-record.schema.json")
  return $written
}
