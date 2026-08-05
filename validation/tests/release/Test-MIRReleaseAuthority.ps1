# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $MirLegacyScriptRoot "..")).Path
. (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
foreach ($module in @("Core", "Records", "Planner", "Views")) {
  . (Join-Path $repo "tools/lib/control/$module.ps1")
}

& (Join-Path $repo "validation/tests/release/Test-MIRReleaseWorkReconciliation.ps1") -RepoRoot $repo

function Assert-MIRField($Object, [string]$Name, $Expected, [string]$Scope) {
  if ([string]$Object.$Name -ne [string]$Expected) {
    throw "$Scope field '$Name' changed. Expected '$Expected', got '$($Object.$Name)'."
  }
}

function Get-MIRReleaseProofSha256 {
  param([Parameter(Mandatory)][string]$Path, [string]$DigestPolicy = "raw")
  if ($DigestPolicy -eq "utf8-lf") {
    $text = (Get-Content -Raw -LiteralPath $Path).Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
  }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-MIRReleaseProofFiles {
  param([Parameter(Mandatory)]$Release)
  foreach ($group in @($Release.proofs.PSObject.Properties)) {
    foreach ($proof in @($group.Value)) {
      if ($null -eq $proof -or $null -eq $proof.PSObject.Properties["path"]) { continue }
      $proofPath = Join-Path $repo ([string]$proof.path)
      if (-not (Test-Path -LiteralPath $proofPath -PathType Leaf)) { throw "Release proof is missing: $($proof.path)" }
      if ($null -ne $proof.PSObject.Properties["sha256"]) {
        $policy = if ($null -ne $proof.PSObject.Properties["digest_policy"]) { [string]$proof.digest_policy } else { "raw" }
        if ((Get-MIRReleaseProofSha256 -Path $proofPath -DigestPolicy $policy) -ne [string]$proof.sha256) {
          throw "Release proof hash changed: $($proof.path)"
        }
      }
    }
  }
}

function Assert-MIRReleaseTag {
  param([Parameter(Mandatory)]$Release)
  $tagProof = @($Release.proofs.tag)
  if ($tagProof.Count -ne 1) { throw "Release $($Release.release) requires exactly one annotated-tag proof." }
  $tagName = [string]$tagProof[0].name
  $tagCommit = (& git -C $repo rev-parse "$tagName^{}").Trim()
  $tagObject = (& git -C $repo rev-parse "$tagName^{tag}").Trim()
  if ($LASTEXITCODE -ne 0 -or [string]$tagProof[0].commit -ne $tagCommit -or [string]$tagProof[0].tag_object -ne $tagObject) {
    throw "ReleaseRecord tag proof disagrees with Git for $tagName."
  }
}
$records = Assert-MIRCPRecords -RepoRoot $repo
$null = Update-MIRCPViews -RepoRoot $repo -Check
$null = Assert-MIRCPPackageFreeze -RepoRoot $repo -AllLocks
$canonical = Get-MIRCPCurrentRelease -Role canonical -RepoRoot $repo
$currentRoles = Read-MIRCPJson -Path "path:releases.current" -RepoRoot $repo
$taggedModern = Get-MIRCPReleaseByVersion -Release ([string]$currentRoles.roles.tagged_factorio_2_1) -RepoRoot $repo
$publishedModern = Get-MIRCPReleaseByVersion -Release ([string]$currentRoles.roles.published_factorio_2_1) -RepoRoot $repo
$publishedBackport = Get-MIRCPReleaseByVersion -Release ([string]$currentRoles.roles.published_factorio_2_0) -RepoRoot $repo
$backport = Get-MIRCPCurrentRelease -Role backport_calibration -RepoRoot $repo
$info = Read-MIRCPJson -Path "info.json" -RepoRoot $repo

if ([string]$canonical.release -ne [string]$info.version -or [string]$canonical.target -ne [string]$info.factorio_version) {
  throw "Canonical release authority must bind the package version and Factorio target in info.json."
}
$releaseStates = @((Get-MIRCPPolicy -RepoRoot $repo).release_states | ForEach-Object { [string]$_ })
$canonicalStateIndex = [Array]::IndexOf($releaseStates, [string]$canonical.state)
$packageBuiltStateIndex = [Array]::IndexOf($releaseStates, "package-built")
if ($canonicalStateIndex -lt 0) {
  throw "Canonical release authority has an unknown state: $($canonical.state)."
}
$canonicalHasPackage = $canonicalStateIndex -ge $packageBuiltStateIndex
if (-not $canonicalHasPackage -and @($canonical.package.PSObject.Properties).Count -ne 0) {
  throw "A pre-package canonical release must not claim immutable package identity."
}
foreach ($row in @(
  [pscustomobject]@{record=$taggedModern;target="2.1";minimum="tagged";role="tagged Factorio 2.1"},
  [pscustomobject]@{record=$publishedModern;target="2.1";minimum="published";role="published Factorio 2.1"},
  [pscustomobject]@{record=$publishedBackport;target="2.0";minimum="published";role="published Factorio 2.0"}
)) {
  if ([string]$row.record.target -ne [string]$row.target -or
      [Array]::IndexOf($releaseStates, [string]$row.record.state) -lt [Array]::IndexOf($releaseStates, [string]$row.minimum)) {
    throw "$($row.role) authority is not an admitted immutable release."
  }
}
if ([string]$backport.target -ne "2.0" -or [string]$backport.release -ne [string]$publishedBackport.release -or
    [string]$backport.candidate_id -ne [string]$publishedBackport.candidate_id) {
  throw "Current Factorio 2.0 maintenance authority must bind the published target baseline."
}

Assert-MIRReleaseTag -Release $taggedModern
Assert-MIRReleaseTag -Release $publishedBackport
foreach ($release in @($canonical, $backport, $taggedModern, $publishedModern, $publishedBackport) | Sort-Object release -Unique) {
  Assert-MIRReleaseProofFiles -Release $release
}

if ($canonicalHasPackage) {
  $archivePath = Join-Path $repo ([string]$canonical.package.archive)
  if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw "Canonical candidate archive is missing." }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
  try { $entryCount = @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count }
  finally { $zip.Dispose() }
  if ((Get-Item -LiteralPath $archivePath).Length -ne [long]$canonical.package.bytes -or
      $entryCount -ne [int]$canonical.package.entries -or
      (Get-MIRFileSha256 -Path $archivePath) -ne [string]$canonical.package.archive_sha256 -or
      (Get-MIRZipContentFingerprint -Path $archivePath) -ne [string]$canonical.package.content_sha256) {
    throw "Canonical candidate archive no longer matches its ReleaseRecord."
  }

  $sourceTree = (& git -C $repo show -s --format=%T ([string]$canonical.package.source_commit)).Trim()
  if ($LASTEXITCODE -ne 0 -or $sourceTree -ne [string]$canonical.package.source_tree) { throw "Canonical package source tree differs from ReleaseRecord." }
  & git -C $repo merge-base --is-ancestor ([string]$canonical.package.source_commit) HEAD
  if ($LASTEXITCODE -ne 0) { throw "Canonical package source is not an ancestor of release-engineering HEAD." }
  if (Test-MIRPackageSourceGitDirty -RepoRoot $repo) { throw "Package-visible source is dirty." }
}

$ledger = Read-MIRCPJson -Path ".mir/releases.json" -RepoRoot $repo
if ([string]$ledger.authority -ne "canonical-release-ledger" -or -not [bool]$ledger.rules.typed_release_records_are_authoritative) {
  throw "Legacy release ledger is not a generated compatibility projection."
}
$modern = $ledger.development."factorio-2.1"
foreach ($field in @("mir_version", "candidate_id", "archive_sha256", "package_source_commit", "package_source_tree", "package_source_sha256")) {
  $expected = switch ($field) {
    "mir_version" { $canonical.release }
    "candidate_id" { $canonical.candidate_id }
    "archive_sha256" { $canonical.package.archive_sha256 }
    "package_source_commit" { $canonical.package.source_commit }
    "package_source_tree" { $canonical.package.source_tree }
    "package_source_sha256" { $canonical.package.source_sha256 }
  }
  Assert-MIRField $modern $field $expected "Generated canonical projection"
}
if ([string]$modern.publication_status -ne [string]$canonical.state -or [string]$modern.protected_qualification -ne "pending") {
  throw "Generated canonical projection obscures the current release state or protected-qualification gate."
}

$releaseNotes = Get-Content -Raw -LiteralPath (Join-Path $repo ([string]$canonical.release_notes))
if ($canonicalHasPackage -and ($releaseNotes -notmatch 'MIR-CONTROL-PLANE-IDENTITY:BEGIN' -or $releaseNotes -notmatch [regex]::Escape([string]$canonical.package.archive_sha256))) {
  throw "Release notes do not contain the generated immutable identity block."
}
Write-Host "[ok] typed release records, transitions, immutable tag, package locks, evidence hashes, and generated release views agree."

$freezePacket = Join-Path $repo ".mir/releases/freezes/3.2.5-D1.json"
if (Test-Path -LiteralPath $freezePacket -PathType Leaf) {
  & (Join-Path $repo "validation/tests/release/Test-MIRSourceFreezePacket.ps1") -RepoRoot $repo
}
