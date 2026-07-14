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
if ([string]$info.version -ne [string]$lock.mir_version -or [string]$info.factorio_version -ne [string]$lock.target) {
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
