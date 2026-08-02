param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$lockPath = Join-Path $RepoRoot ".mir\backport-source-lock.json"
if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
  Write-Host "[skip] MIR backport source lock is not present on this branch."
  return
}

function Assert-MIRSourceLockCommit {
  param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Commit)
  if ($Commit -notmatch '^[0-9a-f]{40}$') { throw "$Name must be a full Git commit SHA." }
  & git -C $RepoRoot cat-file -e "$Commit`^{commit}"
  if ($LASTEXITCODE -ne 0) { throw "$Name is unavailable: $Commit" }
}

function Get-MIRSourceLockMapNames {
  param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Name)
  if ($null -eq $Value -or $Value -isnot [pscustomobject]) { throw "$Name must be a JSON object." }
  return @(
    $Value.PSObject.Properties.Name |
      ForEach-Object { ([string]$_).Replace("\", "/") } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      Sort-Object -Unique
  )
}

$lock = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json
if ([int]$lock.schema -eq 4 -and [int]$lock.projection_schema -eq 3) {
  foreach ($field in @("candidate_id", "mir_version", "target", "target_profile_sha256", "release_notes", "candidate_document", "playtest_guide")) {
    if ([string]::IsNullOrWhiteSpace([string]$lock.$field)) { throw "Published backport source lock is missing $field." }
  }
  if ([string]$lock.candidate_id -ne "2.5-P11" -or [string]$lock.mir_version -ne "2.5.0" -or
      [string]$lock.target -ne "2.0" -or [string]$lock.candidate.class -ne "immutable-published-release" -or
      [int]$lock.candidate.forbidden_entries -ne 0) {
    throw "Published backport source lock does not describe the immutable MIR 2.5.0/P11 release."
  }

  foreach ($commitField in @(
    [pscustomobject]@{name="baseline.commit"; value=[string]$lock.baseline.commit},
    [pscustomobject]@{name="portable_source.commit"; value=[string]$lock.portable_source.commit},
    [pscustomobject]@{name="projection.package_source_commit"; value=[string]$lock.projection.package_source_commit}
  )) {
    Assert-MIRSourceLockCommit -Name $commitField.name -Commit $commitField.value
  }

  $baselineTagCommit = (& git -C $RepoRoot rev-list -n 1 ([string]$lock.baseline.reference)).Trim()
  if ($LASTEXITCODE -ne 0 -or $baselineTagCommit -ne [string]$lock.baseline.commit) {
    throw "Published backport baseline tag does not resolve to its locked commit."
  }
  $portableTagCommit = (& git -C $RepoRoot rev-list -n 1 ([string]$lock.portable_source.tag)).Trim()
  if ($LASTEXITCODE -ne 0) { throw "Published backport portable-source tag is unavailable." }
  & git -C $RepoRoot merge-base --is-ancestor ([string]$lock.portable_source.commit) $portableTagCommit
  if ($LASTEXITCODE -ne 0) { throw "Portable package source is not an ancestor of its immutable release tag." }

  $publishedTagCommit = (& git -C $RepoRoot rev-list -n 1 ([string]$lock.mir_version)).Trim()
  if ($LASTEXITCODE -ne 0) { throw "Published target tag $($lock.mir_version) is unavailable." }
  foreach ($ancestor in @([string]$lock.baseline.commit, $portableTagCommit, [string]$lock.projection.package_source_commit)) {
    & git -C $RepoRoot merge-base --is-ancestor $ancestor $publishedTagCommit
    if ($LASTEXITCODE -ne 0) { throw "Published target tag omits required dual-parent/projection ancestor $ancestor." }
  }

  $projectionTree = (& git -C $RepoRoot show -s --format=%T ([string]$lock.projection.package_source_commit)).Trim()
  if ($LASTEXITCODE -ne 0 -or $projectionTree -ne [string]$lock.projection.package_source_tree) {
    throw "Published projection source tree differs from the lock."
  }
  $script:repo = $RepoRoot
  . (Join-Path $RepoRoot "scripts/MIRAssurance/Hashing.ps1")
  $projectionHash = Get-MIRAssuranceCommitPackageSourceHash -Commit ([string]$lock.projection.package_source_commit)
  if ($projectionHash -ne [string]$lock.projection.package_source_sha256 -or
      $projectionHash -ne [string]$lock.candidate.content_sha256) {
    throw "Published projection package-source/content identity differs from the lock."
  }

  . (Join-Path $RepoRoot "scripts/validation/PackageIdentity.ps1")
  $targetManifestText = @(
    & git -C $RepoRoot show "$([string]$lock.projection.package_source_commit):.mir/targets.json"
  ) -join "`n"
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($targetManifestText)) {
    throw "Published projection target-profile manifest is unavailable at its package-source commit."
  }
  $targetManifest = $targetManifestText | ConvertFrom-Json
  $targetProfile = $targetManifest.profiles.PSObject.Properties[[string]$lock.target].Value
  if ($null -eq $targetProfile) { throw "Published projection target profile is absent from its commit-bound manifest." }
  $targetProfileHash = Get-MIRTargetProfileFingerprint -Profile $targetProfile
  if ($targetProfileHash -ne [string]$lock.target_profile_sha256) {
    throw "Published projection target profile differs from the lock."
  }

  $adapted = @($lock.projection.adapted_package_paths | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique)
  $actualAdapted = @(
    & git -C $RepoRoot diff --name-only ([string]$lock.portable_source.commit) ([string]$lock.projection.package_source_commit) -- @(Get-MIRPackageSourceRoots) |
      ForEach-Object { ([string]$_).Replace("\", "/") } |
      Sort-Object -Unique
  )
  if ($LASTEXITCODE -ne 0 -or @(Compare-Object -ReferenceObject $adapted -DifferenceObject $actualAdapted).Count -ne 0) {
    throw "Published projection adapted paths do not cover the exact portable-source delta."
  }

  $deltaPath = Join-Path $RepoRoot ([string]$lock.projection.portable_delta_ledger)
  if (-not (Test-Path -LiteralPath $deltaPath -PathType Leaf)) { throw "Published projection portable-delta ledger is missing." }
  $delta = Get-Content -Raw -LiteralPath $deltaPath | ConvertFrom-Json
  if ([int]$delta.schema -ne 1 -or [string]$delta.kind -ne "mir-portable-delta-ledger" -or
      [string]$delta.source.version -ne [string]$lock.portable_source.release -or
      [string]$delta.source.candidate_id -ne [string]$lock.portable_source.candidate_id -or
      [string]$delta.source.package_source_commit -ne [string]$lock.portable_source.commit -or
      [string]$delta.source.archive_sha256 -ne [string]$lock.portable_source.archive_sha256 -or
      [string]$delta.target.version -ne [string]$lock.mir_version -or
      [string]$delta.target.candidate_id -ne [string]$lock.candidate_id -or
      [string]$delta.target.package_source_commit -ne [string]$lock.projection.package_source_commit -or
      [string]$delta.target.archive_sha256 -ne [string]$lock.candidate.archive_sha256 -or
      -not [bool]$delta.rules.wholesale_merge_forbidden -or
      -not [bool]$delta.rules.target_specific_evidence_required -or
      [bool]$delta.rules.factorio_2_1_evidence_reusable) {
    throw "Published projection portable-delta ledger disagrees with the source lock."
  }
  foreach ($path in @(
    [string]$lock.qualification.target_static,
    [string]$lock.qualification.runtime,
    [string]$lock.qualification.manual_review,
    [string]$lock.release_notes,
    [string]$lock.candidate_document,
    [string]$lock.playtest_guide
  )) {
    $publishedObject = "{0}:{1}" -f $publishedTagCommit, $path
    & git -C $RepoRoot cat-file -e $publishedObject 2>$null
    if ($LASTEXITCODE -ne 0) {
      throw "Published projection authority is missing: $path"
    }
  }
  $typedReleasePath = Join-Path $RepoRoot ".mir/releases/$($lock.mir_version).json"
  $typedRelease = Get-Content -Raw -LiteralPath $typedReleasePath | ConvertFrom-Json
  $publicationProof = @($typedRelease.proofs.public_byte_verification)
  if ([string]$typedRelease.candidate_id -ne [string]$lock.candidate_id -or
      [string]$typedRelease.package.source_commit -ne [string]$lock.projection.package_source_commit -or
      [string]$typedRelease.package.archive_sha256 -ne [string]$lock.candidate.archive_sha256 -or
      [string]$typedRelease.package.content_sha256 -ne [string]$lock.candidate.content_sha256 -or
      $publicationProof.Count -ne 1 -or
      [string]$publicationProof[0].path -ne [string]$lock.qualification.publication_receipt -or
      [string]$publicationProof[0].digest_policy -ne "utf8-lf") {
    throw "Published projection typed release/public-byte proof disagrees with the source lock."
  }
  $publicationPath = Join-Path $RepoRoot ([string]$publicationProof[0].path)
  if (-not (Test-Path -LiteralPath $publicationPath -PathType Leaf)) {
    throw "Published projection public-byte receipt is missing."
  }
  $publicationText = (Get-Content -Raw -LiteralPath $publicationPath).Replace("`r`n", "`n").Replace("`r", "`n")
  $publicationHash = [Convert]::ToHexString(
    [Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($publicationText))
  )
  if ($publicationHash -ne [string]$publicationProof[0].sha256) {
    throw "Published projection public-byte receipt differs from its typed immutable digest."
  }
  Write-Host "[ok] MIR 2.5.0/P11 schema-4 source lock binds exact 2.4.9 + 3.2.3 ancestry, package projection, target profile, portable delta, and published evidence."
  return
}
if ([int]$lock.schema -ne 1 -or [int]$lock.projection_schema -ne 1) {
  throw "Unsupported MIR backport source-lock schema."
}

foreach ($field in @(
  "canonical_release", "canonical_release_tag_commit", "canonical_dev_anchor", "canonical_anchor_ref",
  "canonical_package_source_commit", "released_2_0_reference", "released_2_0_tag_commit", "target",
  "mir_version", "target_profile_sha256", "feature_classification", "release_notes",
  "validation_summary", "candidate_seal"
)) {
  if ([string]::IsNullOrWhiteSpace([string]$lock.$field)) { throw "Backport source lock is missing $field." }
}

Assert-MIRSourceLockCommit -Name "canonical_release_tag_commit" -Commit ([string]$lock.canonical_release_tag_commit)
Assert-MIRSourceLockCommit -Name "canonical_dev_anchor" -Commit ([string]$lock.canonical_dev_anchor)
Assert-MIRSourceLockCommit -Name "canonical_package_source_commit" -Commit ([string]$lock.canonical_package_source_commit)
Assert-MIRSourceLockCommit -Name "released_2_0_tag_commit" -Commit ([string]$lock.released_2_0_tag_commit)

$canonicalTag = & git -C $RepoRoot rev-list -n 1 ([string]$lock.canonical_release)
if ($LASTEXITCODE -ne 0 -or [string]$canonicalTag -ne [string]$lock.canonical_release_tag_commit) {
  throw "Canonical release tag $($lock.canonical_release) does not resolve to the locked commit."
}
$released20Tag = & git -C $RepoRoot rev-list -n 1 ([string]$lock.released_2_0_reference)
if ($LASTEXITCODE -ne 0 -or [string]$released20Tag -ne [string]$lock.released_2_0_tag_commit) {
  throw "Released Factorio 2.0 reference $($lock.released_2_0_reference) does not resolve to the locked commit."
}

$anchorRefCommit = & git -C $RepoRoot rev-parse --verify ([string]$lock.canonical_anchor_ref)
if ($LASTEXITCODE -ne 0 -or [string]$anchorRefCommit -ne [string]$lock.canonical_dev_anchor) {
  throw "Canonical anchor ref $($lock.canonical_anchor_ref) is missing or stale."
}
& git -C $RepoRoot merge-base --is-ancestor ([string]$lock.canonical_dev_anchor) HEAD
if ($LASTEXITCODE -ne 0) { throw "Target history does not contain the canonical development anchor." }

$info = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "info.json") | ConvertFrom-Json
$infoTarget = [string]$info.factorio_version
if ([string]::IsNullOrWhiteSpace($infoTarget)) {
  $identityCatalogPath = Join-Path $RepoRoot ".mir\museum-targets.json"
  if (Test-Path -LiteralPath $identityCatalogPath -PathType Leaf) {
    $identityCatalog = Get-Content -Raw -LiteralPath $identityCatalogPath | ConvertFrom-Json
    $identityMuseumTarget = @($identityCatalog.targets | Where-Object { [string]$_.factorio -eq [string]$lock.target }) | Select-Object -First 1
    if ($null -ne $identityMuseumTarget -and [string]$identityMuseumTarget.version -eq [string]$info.version) {
      $infoTarget = [string]$identityMuseumTarget.factorio
    }
  }
}
if ([string]$info.version -ne [string]$lock.mir_version -or $infoTarget -ne [string]$lock.target) {
  throw "Source-lock target identity disagrees with info.json."
}

. (Join-Path $RepoRoot "scripts\validation\PackageIdentity.ps1")
. (Join-Path $RepoRoot "scripts\validation\TargetProfiles.ps1")
$museumCatalogPath = Join-Path $RepoRoot ".mir\museum-targets.json"
$museumTarget = $null
if (Test-Path -LiteralPath $museumCatalogPath -PathType Leaf) {
  Import-Module (Join-Path $RepoRoot "scripts\Museum\MuseumCompiler.psm1") -Force
  $museumCatalog = Get-MIRMuseumCatalog -Path $museumCatalogPath
  $museumTarget = @($museumCatalog.targets | Where-Object { [string]$_.factorio -eq [string]$lock.target }) | Select-Object -First 1
}
if ($null -ne $museumTarget) {
  $profileText = $museumTarget | ConvertTo-Json -Depth 30 -Compress
  $targetHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($profileText + "`n")))
} else {
  $profile = Get-MIRTargetProfile -RepoRoot $RepoRoot -FactorioVersion ([string]$lock.target)
  $targetHash = Get-MIRTargetProfileFingerprint -Profile $profile
}
if ($targetHash -ne [string]$lock.target_profile_sha256) { throw "Target profile fingerprint drifted from the backport source lock." }
if ($null -eq $museumTarget) {
  & (Join-Path $RepoRoot "scripts\Sync-MIRTargetProfiles.ps1") -RepoRoot $RepoRoot -Check
  if ($LASTEXITCODE -ne 0) { throw "Generated target profile source is stale." }
}

$portablePaths = @(Get-MIRSourceLockMapNames -Value $lock.portable_modules -Name "portable_modules")
$adaptedPaths = @(Get-MIRSourceLockMapNames -Value $lock.adapted_modules -Name "adapted_modules")
$targetSpecificPaths = @(Get-MIRSourceLockMapNames -Value $lock.target_specific_modules -Name "target_specific_modules")
$declaredChangedPaths = @($adaptedPaths + $targetSpecificPaths | Sort-Object -Unique)
$roots = @(Get-MIRPackageSourceRoots)
$changedPaths = @(& git -C $RepoRoot diff --name-only ([string]$lock.canonical_dev_anchor) -- @roots)
if ($LASTEXITCODE -ne 0) { throw "Unable to compare target package source with the canonical development anchor." }
$changedPaths = @($changedPaths | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique)
$undeclared = @($changedPaths | Where-Object { $declaredChangedPaths -notcontains $_ })
$stale = @($adaptedPaths | Where-Object { $changedPaths -notcontains $_ })
if ($undeclared.Count -gt 0) { throw "Portable package paths diverged without a declaration: $($undeclared -join ', ')" }
if ($stale.Count -gt 0) { throw "Declared target adapters no longer differ from the canonical anchor: $($stale -join ', ')" }
foreach ($path in $portablePaths) {
  & git -C $RepoRoot diff --quiet ([string]$lock.canonical_dev_anchor) -- $path
  if ($LASTEXITCODE -ne 0) { throw "Portable module diverged without adaptation: $path" }
}

$featurePath = Join-Path $RepoRoot ([string]$lock.feature_classification)
if (-not (Test-Path -LiteralPath $featurePath -PathType Leaf)) { throw "Target feature classification is missing." }
$featureRecord = Get-Content -Raw -LiteralPath $featurePath | ConvertFrom-Json
if ([int]$featureRecord.schema -ne 1 -or [string]$featureRecord.target -ne [string]$lock.target `
    -or [string]$featureRecord.mir_version -ne [string]$lock.mir_version `
    -or [string]$featureRecord.canonical_dev_anchor -ne [string]$lock.canonical_dev_anchor) {
  throw "Target feature classification identity disagrees with the source lock."
}
$allowedClassifications = @("native", "adapted", "generated-fallback", "finite-reconstruction", "omitted-by-capability")
$featureIds = @{}
foreach ($feature in @($featureRecord.features)) {
  $id = [string]$feature.feature_id
  if ([string]::IsNullOrWhiteSpace($id) -or $featureIds.ContainsKey($id)) { throw "Target feature IDs must be present and unique." }
  $featureIds[$id] = $true
  if ([string]$feature.classification -notin $allowedClassifications) { throw "Feature $id has an unknown classification." }
  foreach ($field in @("positive_requirement", "target_result", "implementation_path", "test", "documentation_consequence")) {
    if ([string]::IsNullOrWhiteSpace([string]$feature.$field)) { throw "Feature $id is missing $field." }
  }
}
foreach ($id in @($lock.canonical_features)) {
  if (-not $featureIds.ContainsKey([string]$id)) { throw "Canonical feature lacks a target disposition: $id" }
}

$omittedNames = Get-MIRSourceLockMapNames -Value $lock.omitted_features -Name "omitted_features"
foreach ($name in $omittedNames) {
  $record = $lock.omitted_features.PSObject.Properties[$name].Value
  if ([string]::IsNullOrWhiteSpace([string]$record.positive_requirement) `
      -or [string]::IsNullOrWhiteSpace([string]$record.target_result)) {
    throw "Omitted feature $name lacks a positive capability reason."
  }
}

$releaseNotesPath = Join-Path $RepoRoot ([string]$lock.release_notes)
if (-not (Test-Path -LiteralPath $releaseNotesPath -PathType Leaf)) { throw "Release notes are missing: $($lock.release_notes)" }
$releaseNotes = Get-Content -Raw -LiteralPath $releaseNotesPath
if (-not $releaseNotes.Contains([string]$lock.canonical_dev_anchor)) { throw "Release notes do not cite the current canonical development anchor." }

$sealPath = Join-Path $RepoRoot ([string]$lock.candidate_seal)
if (Test-Path -LiteralPath $sealPath -PathType Leaf) {
  $seal = Get-Content -Raw -LiteralPath $sealPath | ConvertFrom-Json
  if ([string]$seal.mir_version -ne [string]$lock.mir_version -or [string]$seal.target -ne [string]$lock.target) {
    throw "Candidate seal binds another target or MIR version."
  }
  if ([string]$seal.canonical_dev_anchor -ne [string]$lock.canonical_dev_anchor) {
    throw "Candidate seal binds another canonical development anchor."
  }
}

Write-Host "[ok] MIR $($lock.mir_version) is a declared Factorio $($lock.target) projection of $($lock.canonical_release) with $($changedPaths.Count) target-adapted package paths."
