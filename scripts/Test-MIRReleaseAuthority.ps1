$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts/validation/PackageIdentity.ps1")
foreach ($module in @("Core", "Records", "Planner", "Views")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}

function Assert-MIRField($Object, [string]$Name, $Expected, [string]$Scope) {
  if ([string]$Object.$Name -ne [string]$Expected) {
    throw "$Scope field '$Name' changed. Expected '$Expected', got '$($Object.$Name)'."
  }
}

$records = Assert-MIRCPRecords -RepoRoot $repo
$null = Update-MIRCPViews -RepoRoot $repo -Check
$null = Assert-MIRCPPackageFreeze -RepoRoot $repo -AllLocks
$canonical = Get-MIRCPCurrentRelease -Role canonical -RepoRoot $repo
$currentRoles = Read-MIRCPJson -Path ".mir/releases/current.json" -RepoRoot $repo
$taggedModern = Get-MIRCPReleaseByVersion -Release ([string]$currentRoles.roles.tagged_factorio_2_1) -RepoRoot $repo
$backport = Get-MIRCPCurrentRelease -Role backport_calibration -RepoRoot $repo
$info = Read-MIRCPJson -Path "info.json" -RepoRoot $repo

if ([string]$canonical.release -ne [string]$info.version -or [string]$canonical.target -ne [string]$info.factorio_version) {
  throw "Canonical release authority must bind the package version and Factorio target in info.json."
}
$releaseStates = @((Get-MIRCPPolicy -RepoRoot $repo).release_states | ForEach-Object { [string]$_ })
if ([Array]::IndexOf($releaseStates, [string]$canonical.state) -lt [Array]::IndexOf($releaseStates, "package-built")) {
  throw "Canonical release authority must be at least package-built."
}
if ([string]$taggedModern.release -ne "3.2.2" -or [string]$taggedModern.candidate_id -ne "C24" -or [string]$taggedModern.state -ne "tagged") {
  throw "Tagged Factorio 2.1 authority must retain immutable MIR 3.2.2 C24."
}
if ([string]$backport.release -ne "2.5.0" -or [string]$backport.candidate_id -ne "2.5-P9" -or [string]$backport.state -ne "focused-qualified") {
  throw "Backport calibration authority must bind focused-qualified MIR 2.5.0 P9."
}

$tagCommit = (& git -C $repo rev-parse '3.2.2^{}').Trim()
$tagObject = (& git -C $repo rev-parse '3.2.2^{tag}').Trim()
if ($LASTEXITCODE -ne 0 -or $tagCommit -ne "1138ed55ad7ad42e38cf9e821d1d4e7de5df6378" -or $tagObject -ne "e5b2a85a23e6aa765759a47b43b66e053ad92077") {
  throw "Annotated tag 3.2.2 no longer resolves to its immutable commit and tag object."
}
$tagProof = @($taggedModern.proofs.tag)
if ($tagProof.Count -ne 1 -or [string]$tagProof[0].commit -ne $tagCommit -or [string]$tagProof[0].tag_object -ne $tagObject) {
  throw "ReleaseRecord tag proof disagrees with Git."
}

foreach ($proofGroup in @("focused_qualification", "candidate_qualification", "manual_acceptance")) {
  if ($null -eq $taggedModern.proofs.PSObject.Properties[$proofGroup]) { continue }
  foreach ($proof in @($taggedModern.proofs.$proofGroup)) {
    $proofPath = Join-Path $repo ([string]$proof.path)
    if (-not (Test-Path -LiteralPath $proofPath -PathType Leaf)) { throw "Release proof is missing: $($proof.path)" }
    if ((Get-FileHash -LiteralPath $proofPath -Algorithm SHA256).Hash -ne [string]$proof.sha256) { throw "Release proof hash changed: $($proof.path)" }
  }
}

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
if ($releaseNotes -notmatch 'MIR-CONTROL-PLANE-IDENTITY:BEGIN' -or $releaseNotes -notmatch [regex]::Escape([string]$canonical.package.archive_sha256)) {
  throw "Release notes do not contain the generated immutable identity block."
}
Write-Host "[ok] typed release records, transitions, immutable tag, package locks, evidence hashes, and generated release views agree."
