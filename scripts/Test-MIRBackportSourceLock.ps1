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
if ([int]$lock.schema -ne 3 -or [int]$lock.projection_schema -ne 2) {
  throw "Unsupported MIR backport source-lock schema."
}
foreach ($field in @("candidate_id", "mir_version", "target", "target_profile_sha256", "release_notes", "playtest_guide")) {
  if ([string]::IsNullOrWhiteSpace([string]$lock.$field)) { throw "Backport source lock is missing $field." }
}
foreach ($section in @("baseline", "portable_source", "lineage", "projection", "candidate", "upgrade_contract", "qualification")) {
  if ($null -eq $lock.$section) { throw "Backport source lock is missing $section." }
}

if ([string]$lock.lineage.policy -ne "canonical-tag-projection") {
  throw "Backport source lock must use canonical-tag-projection lineage policy."
}
if ([string]$lock.lineage.state -eq "provisional-content-projection") {
  if ([string]$lock.lineage.canonical_release_tag_status -ne "pending" -or
      [bool]$lock.lineage.portable_source_commit_is_ancestor) {
    throw "Provisional backport lineage must record a pending canonical tag and no ancestry claim."
  }
} elseif ([string]$lock.lineage.state -eq "canonical-tag-descendant") {
  $canonicalTag = [string]$lock.lineage.canonical_release_tag
  & git -C $RepoRoot rev-parse --verify "$canonicalTag`^{commit}" 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Canonical backport release tag does not exist: $canonicalTag" }
  & git -C $RepoRoot merge-base --is-ancestor $canonicalTag ([string]$lock.projection.package_source_commit)
  if ($LASTEXITCODE -ne 0) { throw "Backport package source is not a descendant of canonical tag $canonicalTag." }
} else {
  throw "Unsupported backport lineage state: $($lock.lineage.state)"
}

$baselineCommit = [string]$lock.baseline.commit
$portableCommit = [string]$lock.portable_source.commit
$projectionCommit = [string]$lock.projection.package_source_commit
Assert-MIRCommit -Name "baseline.commit" -Commit $baselineCommit
Assert-MIRCommit -Name "portable_source.commit" -Commit $portableCommit
Assert-MIRCommit -Name "projection.package_source_commit" -Commit $projectionCommit
Assert-MIRAncestor -Name "Published 2.4.9 baseline" -Commit $baselineCommit
Assert-MIRAncestor -Name "2.5 package-source projection" -Commit $projectionCommit

$baselineRef = (& git -C $RepoRoot rev-list -n 1 ([string]$lock.baseline.reference)).Trim()
if ($LASTEXITCODE -ne 0 -or $baselineRef -ne $baselineCommit) {
  throw "Baseline reference $($lock.baseline.reference) does not resolve to the locked commit."
}
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
  throw "The C16-to-2.5 package delta is not the exact declared adapter set."
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

$info = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "info.json") | ConvertFrom-Json
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
if ([string]$lock.qualification.manual_review -ne "pending" `
    -or [string]$lock.qualification.protected_qualification -ne "pending" `
    -or [string]$lock.qualification.publication -ne "unreleased") {
  throw "The provisional 2.5 candidate must remain unreviewed, unsealed, and unreleased."
}

foreach ($docRelative in @([string]$lock.release_notes, [string]$lock.playtest_guide)) {
  $docPath = Join-Path $RepoRoot $docRelative
  if (-not (Test-Path -LiteralPath $docPath -PathType Leaf)) { throw "Backport authority document is missing: $docRelative" }
  $docText = Get-Content -Raw -LiteralPath $docPath
  foreach ($identity in @($baselineCommit, $portableCommit, $projectionCommit, [string]$lock.candidate.archive_sha256)) {
    if (-not $docText.Contains($identity)) { throw "$docRelative does not cite required identity $identity" }
  }
}

Write-Host "[ok] MIR $($lock.mir_version) $($lock.candidate_id) is an exact Factorio $($lock.target) projection of C16."
Write-Host "[ok] Baseline: $baselineCommit; portable source: $portableCommit; projection: $projectionCommit."
Write-Host "[ok] Adapted package paths: $($adaptedActual -join ', ')."
