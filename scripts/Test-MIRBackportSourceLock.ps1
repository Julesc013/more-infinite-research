[CmdletBinding()]
param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$lockPath = Join-Path $RepoRoot ".mir\backport-source-lock.json"
if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
  Write-Host "[skip] MIR backport source lock is not present on this branch."
  return
}

function Assert-MIRCommit {
  param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Commit)
  if ($Commit -notmatch '^[0-9a-f]{40}$') { throw "$Name must be a full Git commit SHA." }
  & git -C $RepoRoot cat-file -e "$Commit`^{commit}"
  if ($LASTEXITCODE -ne 0) { throw "$Name is unavailable: $Commit" }
}

function Assert-MIRAncestor {
  param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Commit)
  & git -C $RepoRoot merge-base --is-ancestor $Commit HEAD
  if ($LASTEXITCODE -ne 0) { throw "$Name is not an ancestor of the current qualification source: $Commit" }
}

function Get-MIRZipFileCount {
  param([Parameter(Mandatory)][string]$Path)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
  try { return @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count }
  finally { $zip.Dispose() }
}

$lock = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json
$info = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'info.json') | ConvertFrom-Json
if ([string]$info.factorio_version -eq '2.0' -and [string]$info.version -eq '2.5.9') {
  # The terminal shadow is a deterministic projection from its own explicit
  # package-source authority.  Preserve and verify the immutable 2.5.5 lock,
  # but do not invent a linear Git ancestry between independent projections.
  if ([int]$lock.schema -ne 5 -or [int]$lock.projection_schema -ne 4 -or
      [string]$lock.mir_version -ne '2.5.5' -or [string]$lock.candidate_id -ne '2.5-P12' -or
      [string]$lock.target -ne '2.0' -or
      [string]$lock.projection.package_source_commit -ne '689940f436b004cf4e5981f1944ddb04eaa17367' -or
      [string]$lock.projection.package_source_tree -ne '512f6d74d67f99526211247e7ede09b8619f7f3f' -or
      [string]$lock.projection.package_source_sha256 -ne '047B3442067FEA6D43EEE8DE4C79BE6FD265B92A059B546F6EC4D5C986CCF154' -or
      [string]$lock.candidate.archive_sha256 -ne '03DFC05F94435FAACB86F19D1BF0BCD160C515C46B8372C483EEBAEB5208A41C' -or
      [string]$lock.candidate.content_sha256 -ne '047B3442067FEA6D43EEE8DE4C79BE6FD265B92A059B546F6EC4D5C986CCF154') {
    throw 'The terminal shadow does not retain the exact immutable 2.5.5 source lock.'
  }
  foreach ($row in @(
    @{Name='baseline.commit'; Commit=[string]$lock.baseline.commit},
    @{Name='portable_source.commit'; Commit=[string]$lock.portable_source.commit},
    @{Name='projection.package_source_commit'; Commit=[string]$lock.projection.package_source_commit}
  )) { Assert-MIRCommit -Name $row.Name -Commit $row.Commit }
  $baselineRef = (& git -C $RepoRoot rev-list -n 1 ([string]$lock.baseline.reference)).Trim()
  if ($LASTEXITCODE -ne 0 -or $baselineRef -ne [string]$lock.baseline.commit) {
    throw 'The immutable 2.5.0 reference no longer resolves to the locked baseline.'
  }
  $projectionTree = (& git -C $RepoRoot show -s --format=%T ([string]$lock.projection.package_source_commit)).Trim()
  if ($LASTEXITCODE -ne 0 -or $projectionTree -ne [string]$lock.projection.package_source_tree) {
    throw 'The immutable 2.5.5 package-source tree differs from its retained lock.'
  }

  . (Join-Path $RepoRoot 'scripts\validation\PackageIdentity.ps1')
  . (Join-Path $RepoRoot 'scripts\validation\TargetProfiles.ps1')
  $lockedArchive = Join-Path $RepoRoot ([string]$lock.candidate.archive)
  if (-not (Test-Path -LiteralPath $lockedArchive -PathType Leaf)) {
    $commonGitDir = (& git -C $RepoRoot rev-parse --path-format=absolute --git-common-dir).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commonGitDir)) {
      throw 'Unable to resolve the main-worktree custody path for immutable 2.5.5.'
    }
    $mainWorktree = Split-Path -Parent $commonGitDir
    $lockedArchive = Join-Path $mainWorktree 'dist\more-infinite-research_2.5.5.zip'
  }
  if (-not (Test-Path -LiteralPath $lockedArchive -PathType Leaf) -or
      (Get-MIRFileSha256 -Path $lockedArchive) -ne [string]$lock.candidate.archive_sha256 -or
      (Get-MIRZipContentFingerprint -Path $lockedArchive) -ne [string]$lock.candidate.content_sha256 -or
      (Get-Item -LiteralPath $lockedArchive).Length -ne [long]$lock.candidate.bytes -or
      (Get-MIRZipFileCount -Path $lockedArchive) -ne [int]$lock.candidate.entries) {
    throw 'The immutable 2.5.5 archive differs from its retained source lock.'
  }
  $profile = Get-MIRTargetProfile -RepoRoot $RepoRoot -FactorioVersion '2.0'
  if ((Get-MIRTargetProfileFingerprint -Profile $profile) -ne [string]$lock.target_profile_sha256) {
    throw 'The Factorio 2.0 target profile drifted from the immutable 2.5.5 lock.'
  }

  $manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir\releases\terminal\shadows\2.5.9\package-manifest.json') | ConvertFrom-Json -Depth 100
  $development = $manifest.source.performance_transition.development_package
  $shadowSourceCommit = [string]$development.package_source_commit
  if ([int]$manifest.schema -ne 1 -or [string]$manifest.kind -ne 'Mir3TerminalPackageManifestV1' -or
      [string]$manifest.release -ne '2.5.9' -or [string]$manifest.target -ne '2.0' -or
      $manifest.source_frozen -ne $false -or $null -ne $manifest.candidate_id -or
      [string]$manifest.source.immutable_dot5_predecessor.commit -ne '27877275854eb131efeb42672d3676c9c513c85e' -or
      $shadowSourceCommit -ne '990e0135aed25b9306bf282eb086685c8b63f782' -or
      [string]$development.package_source_sha256 -ne '4D1FA997DB6F485ED9F6D295FDDF32F68A3B436BB17FDABFEE9CC4972860E59E' -or
      [string]$development.archive_sha256 -ne '3EA775054F35BBBB6B2DE925E519CF7E06DD9B6C34D6DCC4A074191AF0E0A8B2') {
    throw 'The 2.5.9 shadow manifest does not bind its exact independent package-source authority.'
  }
  Assert-MIRCommit -Name '2.5.9 shadow package source' -Commit $shadowSourceCommit
  Assert-MIRAncestor -Name '2.5.9 shadow package source' -Commit $shadowSourceCommit
  $roots = @(Get-MIRPackageSourceRoots)
  & git -C $RepoRoot diff --quiet $shadowSourceCommit HEAD -- @roots
  if ($LASTEXITCODE -ne 0 -or (Test-MIRPackageSourceGitDirty -RepoRoot $RepoRoot)) {
    throw 'Qualification work changed package roots after the exact 2.5.9 shadow source.'
  }
  if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -ne [string]$development.package_source_sha256) {
    throw 'Current package roots do not reproduce the exact 2.5.9 shadow source.'
  }
  Write-Host '[ok] MIR 2.5.9 preserves the immutable 2.5.5 source lock and binds an explicit independent shadow lineage.'
  return
}
if ([int]$lock.schema -eq 5) {
  if ([int]$lock.projection_schema -ne 4 -or [string]$lock.mir_version -ne "2.5.5" -or
      [string]$lock.candidate_id -ne "2.5-P12" -or [string]$lock.target -ne "2.0") {
    throw "MIR 2.5.5 source-lock identity is invalid."
  }

  $baselineCommit = [string]$lock.baseline.commit
  $portableCommit = [string]$lock.portable_source.commit
  $projectionCommit = [string]$lock.projection.package_source_commit
  foreach ($row in @(
    @{Name="baseline.commit"; Commit=$baselineCommit},
    @{Name="portable_source.commit"; Commit=$portableCommit},
    @{Name="projection.package_source_commit"; Commit=$projectionCommit}
  )) { Assert-MIRCommit -Name $row.Name -Commit $row.Commit }
  Assert-MIRAncestor -Name "Published 2.5.0 baseline" -Commit $baselineCommit
  Assert-MIRAncestor -Name "2.5.5 package-source projection" -Commit $projectionCommit

  $baselineRef = (& git -C $RepoRoot rev-list -n 1 ([string]$lock.baseline.reference)).Trim()
  if ($LASTEXITCODE -ne 0 -or $baselineRef -ne $baselineCommit) {
    throw "Baseline reference $($lock.baseline.reference) does not resolve to the locked commit."
  }
  if ([bool]$lock.lineage.portable_source_commit_is_ancestor -or
      [string]$lock.lineage.state -ne "exact-c32-package-source-bound-local-tag-pending" -or
      -not [bool]$lock.lineage.final_release_requires_local_3_2_5_tag_parent) {
    throw "The 2.5.5 lock must truthfully retain its pending local 3.2.5 tag-parent obligation."
  }

  $projectionTree = (& git -C $RepoRoot show -s --format=%T $projectionCommit).Trim()
  if ($LASTEXITCODE -ne 0 -or $projectionTree -ne [string]$lock.projection.package_source_tree) {
    throw "The locked 2.5.5 package-source tree does not match its commit."
  }

  . (Join-Path $RepoRoot "scripts\validation\PackageIdentity.ps1")
  . (Join-Path $RepoRoot "scripts\validation\TargetProfiles.ps1")
  $roots = @(Get-MIRPackageSourceRoots)
  & git -C $RepoRoot diff --quiet $projectionCommit HEAD -- @roots
  if ($LASTEXITCODE -ne 0) { throw "Qualification commits changed package roots after the locked 2.5.5 projection." }
  if (Test-MIRPackageSourceGitDirty -RepoRoot $RepoRoot) { throw "Package roots are dirty; the 2.5.5 projection cannot be verified." }
  if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -ne [string]$lock.projection.package_source_sha256) {
    throw "The projected 2.5.5 package source hash drifted."
  }

  $adaptedActual = @(& git -C $RepoRoot diff-tree --no-commit-id --name-only -r $projectionCommit)
  if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate the 2.5.5 target transition."
  }
  $unclassified = @($adaptedActual | Where-Object {
    $path = ([string]$_).Replace("\", "/")
    @($lock.projection.adapted_package_path_patterns | Where-Object { $path -like ([string]$_) }).Count -eq 0
  })
  if ($unclassified.Count -gt 0) { throw "Unclassified 2.5.5 target paths: $($unclassified -join ', ')" }

  $deltaPath = Join-Path $RepoRoot ([string]$lock.projection.portable_delta_ledger)
  if (-not (Test-Path -LiteralPath $deltaPath -PathType Leaf)) { throw "The 2.5.5 portable-delta ledger is missing." }
  $delta = Get-Content -Raw -LiteralPath $deltaPath | ConvertFrom-Json
  if ([int]$delta.schema -ne 2 -or [string]$delta.kind -ne "mir-portable-delta-ledger" -or
      [string]$delta.source.version -ne "3.2.5" -or [string]$delta.source.candidate_id -ne "C32" -or
      [string]$delta.target.version -ne "2.5.5" -or [string]$delta.target.candidate_id -ne "2.5-P12" -or
      [string]$delta.target.package_source_commit -ne $projectionCommit -or
      -not [bool]$delta.rules.unclassified_path_forbidden -or -not [bool]$delta.rules.unclassified_semantic_forbidden) {
    throw "The 2.5.5 portable-delta ledger identity or fail-closed rules are invalid."
  }
  $allowedDispositions = @(
    "shared-unchanged", "shared-with-target-adapter", "target-native-equivalent", "compiled-out",
    "finite-substitute", "omitted-by-capability", "release-evidence-only", "intentionally-excluded",
    "unsupported-with-evidence"
  )
  if (@($delta.changes | Where-Object { [string]$_.disposition -notin $allowedDispositions }).Count -gt 0) {
    throw "The 2.5.5 portable-delta ledger uses an unsupported disposition."
  }

  $profile = Get-MIRTargetProfile -RepoRoot $RepoRoot -FactorioVersion "2.0"
  if ((Get-MIRTargetProfileFingerprint -Profile $profile) -ne [string]$lock.target_profile_sha256) {
    throw "The Factorio 2.0 target profile fingerprint drifted."
  }
  & (Join-Path $RepoRoot "scripts\Sync-MIRTargetProfiles.ps1") -RepoRoot $RepoRoot -Check
  if ($LASTEXITCODE -ne 0) { throw "Generated target-profile Lua is stale." }

  if ([string]$info.version -ne [string]$lock.mir_version -or [string]$info.factorio_version -ne [string]$lock.target) {
    throw "The 2.5.5 source lock disagrees with info.json."
  }
  $archivePath = Join-Path $RepoRoot ([string]$lock.candidate.archive)
  if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw "The 2.5.5 candidate archive is missing." }
  if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne [string]$lock.candidate.archive_sha256 -or
      (Get-MIRZipContentFingerprint -Path $archivePath) -ne [string]$lock.candidate.content_sha256 -or
      (Get-Item -LiteralPath $archivePath).Length -ne [long]$lock.candidate.bytes -or
      (Get-MIRZipFileCount -Path $archivePath) -ne [int]$lock.candidate.entries) {
    throw "The 2.5.5 candidate archive identity disagrees with its source lock."
  }
  if ([string]$lock.upgrade_contract.mandatory_predecessor -ne "2.5.0" -or
      [string]$lock.qualification.protected_qualification -ne "pending-post-outage" -or
      [string]$lock.qualification.publication -ne "pending") {
    throw "The 2.5.5 upgrade or outage qualification boundary is invalid."
  }
  foreach ($docRelative in @([string]$lock.release_notes, [string]$lock.candidate_document, [string]$lock.playtest_guide)) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $docRelative) -PathType Leaf)) {
      throw "Backport authority document is missing: $docRelative"
    }
  }
  Write-Host "[ok] MIR 2.5.5 2.5-P12 source, target, archive, direct predecessor, and pending outage boundary agree."
  return
}
if ([int]$lock.schema -ne 4 -or [int]$lock.projection_schema -ne 3) {
  throw "Unsupported MIR backport source-lock schema."
}
foreach ($field in @("candidate_id", "mir_version", "target", "target_profile_sha256", "release_notes", "candidate_document", "playtest_guide")) {
  if ([string]::IsNullOrWhiteSpace([string]$lock.$field)) { throw "Backport source lock is missing $field." }
}
foreach ($section in @("baseline", "portable_source", "lineage", "projection", "candidate", "upgrade_contract", "qualification")) {
  if ($null -eq $lock.$section) { throw "Backport source lock is missing $section." }
}

if ([string]$lock.lineage.policy -ne "canonical-semantic-projection" -or
    [string]$lock.lineage.state -ne "tagged-3.2.3-semantic-source-pending-target-qualification" -or
    -not [bool]$lock.lineage.portable_source_commit_is_ancestor -or
    -not [bool]$lock.lineage.prior_target_tag_is_ancestor -or
    -not [bool]$lock.lineage.final_candidate_requires_exact_portable_delta_ledger) {
  throw "Backport source lock must record an honest tagged-3.2.3 semantic projection with literal 2.4.9 and C30 ancestry."
}
if ([string]$lock.portable_source.release -ne "3.2.3" -or
    [string]$lock.portable_source.candidate_id -ne "C30" -or
    [string]$lock.portable_source.tag_status -ne "tagged" -or
    [string]$lock.lineage.canonical_release_tag -ne "3.2.3" -or
    [string]$lock.lineage.canonical_release_tag_status -ne "tagged") {
  throw "The 2.5 source lock must bind tagged MIR 3.2.3 candidate C30."
}

$baselineCommit = [string]$lock.baseline.commit
$portableCommit = [string]$lock.portable_source.commit
$projectionCommit = [string]$lock.projection.package_source_commit
Assert-MIRCommit -Name "baseline.commit" -Commit $baselineCommit
Assert-MIRCommit -Name "portable_source.commit" -Commit $portableCommit
Assert-MIRCommit -Name "projection.package_source_commit" -Commit $projectionCommit
Assert-MIRAncestor -Name "Published 2.4.9 baseline" -Commit $baselineCommit
Assert-MIRAncestor -Name "C30 portable package source" -Commit $portableCommit
Assert-MIRAncestor -Name "2.5 package-source projection" -Commit $projectionCommit

$baselineRef = (& git -C $RepoRoot rev-list -n 1 ([string]$lock.baseline.reference)).Trim()
if ($LASTEXITCODE -ne 0 -or $baselineRef -ne $baselineCommit) {
  throw "Baseline reference $($lock.baseline.reference) does not resolve to the locked commit."
}
$canonicalTag = [string]$lock.lineage.canonical_release_tag
$canonicalTagCommit = (& git -C $RepoRoot rev-list -n 1 $canonicalTag).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($canonicalTagCommit)) {
  throw "Canonical source tag is unavailable: $canonicalTag"
}
& git -C $RepoRoot merge-base --is-ancestor $portableCommit $canonicalTagCommit
if ($LASTEXITCODE -ne 0) { throw "C30 package source is not contained by canonical tag $canonicalTag." }
& git -C $RepoRoot merge-base --is-ancestor $canonicalTagCommit HEAD
if ($LASTEXITCODE -ne 0) { throw "Canonical tag $canonicalTag is not retained in the P11 dual-parent lineage." }
$projectionTree = (& git -C $RepoRoot show -s --format=%T $projectionCommit).Trim()
if ($LASTEXITCODE -ne 0 -or $projectionTree -ne [string]$lock.projection.package_source_tree) {
  throw "The locked 2.5 package-source tree does not match its commit."
}

. (Join-Path $RepoRoot "scripts\validation\PackageIdentity.ps1")
. (Join-Path $RepoRoot "scripts\validation\TargetProfiles.ps1")
$roots = @(Get-MIRPackageSourceRoots)
& git -C $RepoRoot diff --quiet $projectionCommit HEAD -- @roots
if ($LASTEXITCODE -ne 0) { throw "Qualification commits changed package roots after the locked projection commit." }
if (Test-MIRPackageSourceGitDirty -RepoRoot $RepoRoot) { throw "Package roots are dirty; the projection cannot be verified." }

$adaptedExpected = @($lock.projection.adapted_package_paths | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique)
$adaptedActual = @(
  & git -C $RepoRoot diff --name-only $portableCommit $projectionCommit -- @roots |
    ForEach-Object { ([string]$_).Replace("\", "/") } |
    Sort-Object -Unique
)
if ($LASTEXITCODE -ne 0) { throw "Unable to compare the portable source with the target projection." }
$adaptedDelta = @(Compare-Object $adaptedExpected $adaptedActual)
if ($adaptedDelta.Count -gt 0) {
  throw "The C30-to-2.5 package delta is not the exact declared adapter set."
}
$deltaPath = Join-Path $RepoRoot ([string]$lock.projection.portable_delta_ledger)
if (-not (Test-Path -LiteralPath $deltaPath -PathType Leaf)) { throw "Portable-delta ledger is missing." }
$delta = Get-Content -Raw -LiteralPath $deltaPath | ConvertFrom-Json
if ([int]$delta.schema -ne 1 -or [string]$delta.kind -ne "mir-portable-delta-ledger" -or
    [string]$delta.source.version -ne "3.2.3" -or [string]$delta.source.candidate_id -ne "C30" -or
    [string]$delta.source.package_source_commit -ne $portableCommit -or
    [string]$delta.target.version -ne "2.5.0" -or [string]$delta.target.candidate_id -ne "2.5-P11" -or
    [string]$delta.target.package_source_commit -ne $projectionCommit -or
    -not [bool]$delta.rules.wholesale_merge_forbidden -or -not [bool]$delta.rules.target_specific_evidence_required -or
    [bool]$delta.rules.factorio_2_1_evidence_reusable) {
  throw "Portable-delta ledger identity or target-boundary rules are invalid."
}
$expectedDeltaIds = @(
  "c21-concrete-planet-resolver",
  "c24-py-finalizer-ordering",
  "c24-affected-save-planet-recovery",
  "c24-py-synthetic-fixture",
  "c24-py-real-closure",
  "c21-c24-release-assurance",
  "factorio-2.1-metadata-and-effects",
  "c30-platform-ice-progression",
  "c30-structural-logistics",
  "c30-structural-indexing",
  "c30-automatic-action-guard",
  "p11-platform-stream-count-authority",
  "c30-timeboxed-release-assurance"
) | Sort-Object
$actualDeltaIds = @($delta.changes.id | Sort-Object -Unique)
if (($actualDeltaIds -join "|") -ne ($expectedDeltaIds -join "|")) {
  throw "Portable-delta ledger does not classify every governed C21/C24/C30 backport surface exactly once."
}
if ([string](@($delta.changes | Where-Object id -eq "c24-affected-save-planet-recovery")[0].disposition) -ne "omitted-version-specific") {
  throw "The 3.2-only affected-save repair must remain explicitly omitted from the 2.x package line."
}

$sourceHash = Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
if ($sourceHash -ne [string]$lock.projection.package_source_sha256) {
  throw "The projected package source hash drifted: $sourceHash"
}
$profile = Get-MIRTargetProfile -RepoRoot $RepoRoot -FactorioVersion ([string]$lock.target)
$profileHash = Get-MIRTargetProfileFingerprint -Profile $profile
if ($profileHash -ne [string]$lock.target_profile_sha256) { throw "Target profile fingerprint drifted: $profileHash" }
& (Join-Path $RepoRoot "scripts\Sync-MIRTargetProfiles.ps1") -RepoRoot $RepoRoot -Check
if ($LASTEXITCODE -ne 0) { throw "Generated target-profile Lua is stale." }

if ([string]$info.version -ne [string]$lock.mir_version -or [string]$info.factorio_version -ne [string]$lock.target) {
  throw "Source-lock target identity disagrees with info.json."
}

$archivePath = Join-Path $RepoRoot ([string]$lock.candidate.archive)
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw "Candidate archive is missing: $archivePath" }
$archiveItem = Get-Item -LiteralPath $archivePath
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
$contentHash = Get-MIRZipContentFingerprint -Path $archivePath
$entryCount = Get-MIRZipFileCount -Path $archivePath
if ($archiveHash -ne [string]$lock.candidate.archive_sha256 `
    -or $contentHash -ne [string]$lock.candidate.content_sha256 `
    -or $archiveItem.Length -ne [long]$lock.candidate.bytes `
    -or $entryCount -ne [int]$lock.candidate.entries) {
  throw "Candidate archive identity disagrees with the backport source lock."
}

if ([string]$lock.upgrade_contract.mandatory_predecessor -ne "2.4.9" `
    -or [string]$lock.upgrade_contract.oldest_maintained_optional -ne "2.4.5") {
  throw "The 2.5 upgrade contract must require 2.4.9 and retain 2.4.5 as the optional oldest-maintained row."
}
$automatedQualification = ".mir/evidence/2.5.0-local-automated-qualification.json"
$manualQualification = ".mir/evidence/2.5.0-manual-review-attestation.json"
if ([string]$lock.qualification.target_static -ne $automatedQualification `
    -or [string]$lock.qualification.synthetic_py_finalizer -ne $automatedQualification `
    -or [string]$lock.qualification.runtime -ne $automatedQualification `
    -or [string]$lock.qualification.manual_review -ne $manualQualification `
    -or [string]$lock.qualification.protected_qualification -ne "pending-exact-p11" `
    -or [string]$lock.qualification.publication -ne "unreleased") {
  throw "P11 must bind exact local automated/manual qualification while protected and publication gates remain pending."
}
$automatedQualificationPath = Join-Path $RepoRoot $automatedQualification
if (-not (Test-Path -LiteralPath $automatedQualificationPath -PathType Leaf)) {
  throw "P11 local automated qualification authority is missing."
}
$automated = Get-Content -Raw -LiteralPath $automatedQualificationPath | ConvertFrom-Json
if ([int]$automated.schema -ne 1 `
    -or [string]$automated.kind -ne "mir-local-automated-qualification" `
    -or [string]$automated.release -ne "2.5.0" `
    -or [string]$automated.candidate_id -ne "2.5-P11" `
    -or [string]$automated.target -ne "2.0" `
    -or [string]$automated.status -ne "machine-verifiable-passed-manual-and-protected-gates-pending" `
    -or [bool]$automated.release_eligible `
    -or [string]$automated.package_source_commit -ne $projectionCommit `
    -or [string]$automated.candidate.archive_sha256 -ne [string]$lock.candidate.archive_sha256 `
    -or [string]$automated.candidate.package_content_sha256 -ne [string]$lock.candidate.content_sha256 `
    -or [int]$automated.aggregate.passed -ne 126 `
    -or [int]$automated.aggregate.failed -ne 1 `
    -or [string]$automated.aggregate.only_failed_task -ne "manual.release-review" `
    -or [string]$automated.checks.manual_review.status -ne "missing-required-attestation") {
  throw "P11 local automated qualification authority is invalid."
}
$manualQualificationPath = Join-Path $RepoRoot $manualQualification
if (-not (Test-Path -LiteralPath $manualQualificationPath -PathType Leaf)) {
  throw "P11 manual qualification authority is missing."
}
$manual = Get-Content -Raw -LiteralPath $manualQualificationPath | ConvertFrom-Json
if ([int]$manual.schema -ne 2 `
    -or [string]$manual.kind -ne "mir-manual-release-review" `
    -or [string]$manual.status -ne "passed" `
    -or [string]$manual.candidate_sha256 -ne [string]$lock.candidate.archive_sha256 `
    -or [string]$manual.candidate_content_sha256 -ne [string]$lock.candidate.content_sha256 `
    -or [string]$manual.source_commit -ne $projectionCommit `
    -or [string]$manual.factorio_version -ne "2.0.77" `
    -or [string]$manual.reviewer -ne "Julesc013" `
    -or @($manual.items).Count -ne 7 `
    -or @($manual.items | Where-Object { [string]$_.status -ne "passed" }).Count -ne 0) {
  throw "P11 manual qualification authority is invalid."
}

foreach ($docRelative in @([string]$lock.release_notes, [string]$lock.candidate_document, [string]$lock.playtest_guide)) {
  $docPath = Join-Path $RepoRoot $docRelative
  if (-not (Test-Path -LiteralPath $docPath -PathType Leaf)) { throw "Backport authority document is missing: $docRelative" }
  $docText = Get-Content -Raw -LiteralPath $docPath
  foreach ($identity in @($baselineCommit, $portableCommit, $projectionCommit, [string]$lock.candidate.archive_sha256)) {
    if (-not $docText.Contains($identity)) { throw "$docRelative does not cite required identity $identity" }
  }
}

Write-Host "[ok] MIR $($lock.mir_version) $($lock.candidate_id) is an exact Factorio $($lock.target) projection of tagged C30."
Write-Host "[ok] Baseline: $baselineCommit; portable source: $portableCommit; projection: $projectionCommit."
Write-Host "[ok] Adapted package paths: $($adaptedActual -join ', ')."
