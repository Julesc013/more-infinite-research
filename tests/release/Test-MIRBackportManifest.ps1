# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = "",
  [string]$ManifestPath = ".mir/releases/backports/2.5.0.json",
  [switch]$AllowPendingTags
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $MirLegacyScriptRoot "..")).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not [IO.Path]::IsPathRooted($ManifestPath)) { $ManifestPath = Join-Path $RepoRoot $ManifestPath }
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Backport manifest not found: $ManifestPath" }

function Resolve-ManifestCommit {
  param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$Name)
  $resolved = @(& git -C $RepoRoot rev-parse "$Value^{commit}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $resolved.Count -ne 1 -or [string]$resolved[0] -notmatch '^[0-9a-f]{40}$') {
    throw "Unable to resolve $Name commit: $Value"
  }
  return [string]$resolved[0]
}

function Assert-Ancestor {
  param([Parameter(Mandatory)][string]$Ancestor, [Parameter(Mandatory)][string]$Descendant, [Parameter(Mandatory)][string]$Message)
  & git -C $RepoRoot merge-base --is-ancestor $Ancestor $Descendant
  if ($LASTEXITCODE -ne 0) { throw $Message }
}

function Get-CommitJson {
  param([Parameter(Mandatory)][string]$Commit, [Parameter(Mandatory)][string]$Path)
  $text = @(& git -C $RepoRoot show "${Commit}:$Path" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $text.Count -eq 0) { throw "Unable to read $Path at $Commit." }
  return ($text -join "`n") | ConvertFrom-Json
}

$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
$strategy = [string]$manifest.integration.strategy
if (([int]$manifest.schema -eq 1 -and $strategy -ne "dual-parent-target-projection-v1") -or
    ([int]$manifest.schema -eq 2 -and $strategy -ne "integrated-target-successor-v2") -or
    [int]$manifest.schema -notin @(1, 2)) {
  throw "Unsupported MIR backport manifest."
}
foreach ($field in @("target_release", "target_factorio")) {
  if ([string]::IsNullOrWhiteSpace([string]$manifest.$field)) { throw "Backport manifest is missing $field." }
}

$baselineCommit = Resolve-ManifestCommit -Value ([string]$manifest.baseline.tag_commit) -Name "baseline"
$baselineTagCommit = Resolve-ManifestCommit -Value ([string]$manifest.baseline.tag) -Name "baseline tag"
if ($baselineCommit -ne $baselineTagCommit) { throw "Baseline tag does not resolve to the locked commit." }

$sourcePackageCommit = Resolve-ManifestCommit -Value ([string]$manifest.source.package_source_commit) -Name "source package"
$sourceInfo = Get-CommitJson -Commit $sourcePackageCommit -Path "info.json"
if ([string]$sourceInfo.version -ne [string]$manifest.source.release -or [string]$sourceInfo.factorio_version -ne "2.1") {
  throw "Source package commit is not the declared modern release."
}

$sourceTagCommit = ""
$sourceTag = [string]$manifest.source.tag
$sourceTagExists = $true
try { $sourceTagCommit = Resolve-ManifestCommit -Value $sourceTag -Name "source tag" } catch { $sourceTagExists = $false }
if (-not $sourceTagExists) {
  if (-not $AllowPendingTags -or [string]$manifest.source.tag_state -notmatch '^pending') {
    throw "Source release tag is unavailable: $sourceTag"
  }
} else {
  $lockedSourceTag = [string]$manifest.source.tag_commit
  if ($lockedSourceTag -and $lockedSourceTag -ne $sourceTagCommit) { throw "Source tag commit disagrees with the manifest." }
  Assert-Ancestor -Ancestor $sourcePackageCommit -Descendant $sourceTagCommit -Message "Source package commit is not an ancestor of the immutable source tag."
}

$targetPackageCommit = Resolve-ManifestCommit -Value ([string]$manifest.integration.target_package_source_commit) -Name "target package"
if ($strategy -eq "dual-parent-target-projection-v1") {
  $projectionCommit = Resolve-ManifestCommit -Value ([string]$manifest.integration.preintegration_commit) -Name "preintegration"
  $projectionTree = (& git -C $RepoRoot rev-parse "$projectionCommit^{tree}").Trim()
  if ($projectionTree -ne [string]$manifest.integration.preintegration_tree -or
      $projectionTree -ne [string]$manifest.expected_target.integration_tree) {
    throw "Preintegration tree identity disagrees with the manifest."
  }
  Assert-Ancestor -Ancestor $baselineCommit -Descendant $projectionCommit -Message "Preintegration target lineage does not descend from the immutable baseline."
  Assert-Ancestor -Ancestor $targetPackageCommit -Descendant $projectionCommit -Message "Target package source is not an ancestor of the preintegration checkpoint."

  $projectionTag = [string]$manifest.integration.preintegration_tag
  $projectionTagExists = $true
  $projectionTagCommit = ""
  try { $projectionTagCommit = Resolve-ManifestCommit -Value $projectionTag -Name "preintegration tag" } catch { $projectionTagExists = $false }
  if (-not $projectionTagExists) {
    if (-not $AllowPendingTags -or [string]$manifest.integration.preintegration_tag_state -notmatch '^pending') {
      throw "Preintegration archive tag is unavailable: $projectionTag"
    }
  } elseif ($projectionTagCommit -ne $projectionCommit) {
    throw "Preintegration archive tag does not resolve to the locked target commit."
  }
  $sourceLock = Get-CommitJson -Commit $projectionCommit -Path ".mir/backport-source-lock.json"
} else {
  if (-not $sourceTagExists) { throw "Integrated-successor manifests require the immutable modern release tag." }
  $projectionCommit = Resolve-ManifestCommit -Value ([string]$manifest.integration.commit) -Name "integration"
  $projectionTree = (& git -C $RepoRoot rev-parse "$projectionCommit^{tree}").Trim()
  $targetTree = (& git -C $RepoRoot rev-parse "$targetPackageCommit^{tree}").Trim()
  $parents = @(((& git -C $RepoRoot show -s --format=%P $projectionCommit).Trim()) -split ' ')
  if ($projectionTree -ne [string]$manifest.integration.tree -or
      $projectionTree -ne [string]$manifest.expected_target.integration_tree) {
    throw "Integration tree identity disagrees with the manifest."
  }
  if ($targetTree -ne [string]$manifest.expected_target.package_source_tree) {
    throw "Target package-source tree identity disagrees with the manifest."
  }
  if ($parents.Count -ne 2 -or $parents[0] -ne [string]$manifest.integration.first_parent -or
      $parents[1] -ne [string]$manifest.integration.second_parent -or $parents[1] -ne $sourceTagCommit) {
    throw "Integrated-successor parent ordering disagrees with the manifest."
  }
  Assert-Ancestor -Ancestor $baselineCommit -Descendant $projectionCommit -Message "Integration lineage does not descend from the immutable baseline."
  Assert-Ancestor -Ancestor $projectionCommit -Descendant $targetPackageCommit -Message "Target package source is not an integration successor."
  $sourceLockCommit = Resolve-ManifestCommit -Value ([string]$manifest.integration.source_lock_commit) -Name "source lock"
  Assert-Ancestor -Ancestor $targetPackageCommit -Descendant $sourceLockCommit -Message "P11 source lock does not descend from the exact package source."
  $sourceLock = Get-CommitJson -Commit $sourceLockCommit -Path ".mir/backport-source-lock.json"
}
if ([int]$sourceLock.schema -lt 4 -or [string]$sourceLock.portable_source.commit -ne $sourcePackageCommit) {
  throw "Backport source lock does not bind the exact modern package source."
}
if ([string]$sourceLock.projection.package_source_commit -ne $targetPackageCommit) {
  throw "Backport source lock does not bind the exact target package source."
}
if ([string]$sourceLock.portable_source.archive_sha256 -ne [string]$manifest.source.archive_sha256 -or
    [string]$sourceLock.portable_source.source_sha256 -ne [string]$manifest.source.package_source_sha256 -or
    [string]$sourceLock.target_profile_sha256 -ne [string]$manifest.integration.target_profile_sha256) {
  throw "Preintegration source lock disagrees with the modern archive or target profile identity."
}

$declared = @($manifest.package_path_classification | ForEach-Object { ([string]$_.path).Replace("\", "/") } | Sort-Object -Unique)
$adapted = @($sourceLock.projection.adapted_package_paths | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique)
if (@(Compare-Object -ReferenceObject $adapted -DifferenceObject $declared).Count -ne 0) {
  throw "Backport package-path classification is incomplete or stale."
}
$allowedClasses = @("shared-unchanged", "shared-with-target-adapter", "factorio-2.1-only", "release-evidence-only", "intentionally-excluded")
foreach ($entry in @($manifest.package_path_classification)) {
  if ([string]$entry.class -notin $allowedClasses -or [string]::IsNullOrWhiteSpace([string]$entry.reason)) {
    throw "Package-path classification is invalid for $($entry.path)."
  }
}

$script:repo = $RepoRoot
. (Join-Path $RepoRoot "tools\lib\assurance\Core.ps1")
. (Join-Path $RepoRoot "tools\lib\assurance\Hashing.ps1")
. (Join-Path $RepoRoot "tools\lib\validation\PackageIdentity.ps1")
$sourceLayout = Get-MIRPackageSourceLayoutAtCommit -RepoRoot $RepoRoot -Commit $sourcePackageCommit
$targetLayout = Get-MIRPackageSourceLayoutAtCommit -RepoRoot $RepoRoot -Commit $targetPackageCommit
$packageRoots = @(@($sourceLayout.roots) + @($targetLayout.roots) | Sort-Object -Unique)
$actualChanged = @(
  & git -C $RepoRoot diff --name-only $sourcePackageCommit $targetPackageCommit -- @packageRoots |
    ForEach-Object { ([string]$_).Replace("\", "/") } |
    Sort-Object -Unique
)
if ($LASTEXITCODE -ne 0 -or @(Compare-Object -ReferenceObject $declared -DifferenceObject $actualChanged).Count -ne 0) {
  throw "Manifest classifications do not cover the exact modern-to-target package delta."
}
$sourceHash = Get-MIRAssuranceCommitPackageSourceHash -Commit $sourcePackageCommit
$targetHash = Get-MIRAssuranceCommitPackageSourceHash -Commit $targetPackageCommit
if ($sourceHash -ne [string]$manifest.source.package_source_sha256) { throw "Modern package-source identity disagrees with the manifest." }
if ($targetHash -ne [string]$manifest.expected_target.package_content_sha256) { throw "Target package-source identity disagrees with the manifest." }
if ([string]$sourceLock.candidate.archive_sha256 -ne [string]$manifest.expected_target.archive_sha256 -or
    [int64]$sourceLock.candidate.bytes -ne [int64]$manifest.expected_target.bytes -or
    [int]$sourceLock.candidate.entries -ne [int]$manifest.expected_target.entries) {
  throw "Target archive identity disagrees with the preintegration source lock."
}

Write-Host "[ok] MIR $($manifest.target_release) backport manifest binds baseline $($manifest.baseline.release), source $($manifest.source.release), and $($declared.Count) classified package adapters."
