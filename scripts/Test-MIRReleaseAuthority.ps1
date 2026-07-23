param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Read-MIRText {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path = Join-Path $repo $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Release-authority view is missing: $RelativePath"
  }
  return Get-Content -Raw -LiteralPath $path
}

$ledgerPath = Join-Path $repo ".mir\releases.json"
$ledger = Read-MIRText ".mir/releases.json" | ConvertFrom-Json
if ([int]$ledger.schema -ne 1 -or [string]$ledger.authority -ne "canonical-release-ledger") {
  throw ".mir/releases.json is not the canonical release-ledger schema."
}

$modern = $ledger.development."factorio-2.1"
$backport = $ledger.development."factorio-2.0"
$publishedModern = $ledger.published_baselines."factorio-2.1"
$publishedBackport = $ledger.published_baselines."factorio-2.0"
if ([string]$publishedModern.mir_version -ne "3.1.9" -or [string]$publishedModern.tag -ne "3.1.9" -or
    [string]$publishedModern.status -ne "published-frozen") {
  throw "Canonical Factorio 2.1 published baseline must remain immutable MIR 3.1.9."
}
if ([string]$publishedBackport.mir_version -ne "2.4.9" -or [string]$publishedBackport.tag -ne "2.4.9" -or
    [string]$publishedBackport.archive -ne "dist/more-infinite-research_2.4.9.zip" -or
    [string]$publishedBackport.status -ne "published-frozen") {
  throw "Canonical Factorio 2.0 published baseline must remain immutable MIR 2.4.9."
}
if ([string]$modern.mir_version -ne "3.2.0" -or [string]$modern.branch -ne "dev" -or
    [string]$modern.qualification -ne "not-release-qualified") {
  throw "Canonical modern development release must remain MIR 3.2.0 on dev and not release-qualified."
}
$c7Authority = [ordered]@{
  candidate_id = "C7"
  archive = "dist/more-infinite-research_3.2.0.zip"
  archive_bytes = 958994
  archive_entries = 256
  package_source_commit = "b532e91a227cc4b17526edbb1388c7836e0a6dbe"
  package_source_tree = "28c79804f1543961628ccd722931e31305c6d78f"
  package_source_sha256 = "D687ADB304B6A907BB7604085E0C71788E69CDAF6A256F0D4A2269F8382AA7D7"
  archive_sha256 = "1E3CC8016A9DA8F399D01BA6B515DD8CF6D414525F99CC08B08278A077FF8B4B"
  package_content_sha256 = "D687ADB304B6A907BB7604085E0C71788E69CDAF6A256F0D4A2269F8382AA7D7"
}
foreach ($field in $c7Authority.Keys) {
  if ([string]$modern.$field -ne [string]$c7Authority[$field]) {
    throw "Canonical C7 authority field '$field' changed. C8 is required if candidate bytes change."
  }
}
if ([int]$modern.package_source_material.schema -ne 1 -or
    [string]$modern.package_source_material.hash_algorithm -ne "git-commit-normalized-package-v1" -or
    [string]$modern.package_source_material.source_tree -ne [string]$modern.package_source_tree -or
    [int]$modern.package_source_material.file_count -ne 256) {
  throw "Canonical C7 package-source material descriptor must bind its clean source tree and 256 package files."
}
& git -C $repo merge-base --is-ancestor ([string]$modern.package_source_commit) HEAD
if ($LASTEXITCODE -ne 0) { throw "C7 package-source commit is not an ancestor of release-engineering HEAD." }
$packageSourceTree = @(& git -C $repo rev-parse "$([string]$modern.package_source_commit)^{tree}")
if ($LASTEXITCODE -ne 0 -or $packageSourceTree.Count -ne 1 -or [string]$packageSourceTree[0] -ne [string]$modern.package_source_tree) {
  throw "C7 package-source tree does not match the canonical authority row."
}
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
$packageRoots = @(Get-MIRPackageSourceRoots)
$changedPackagePaths = @(& git -C $repo diff --name-only ([string]$modern.package_source_commit) HEAD -- @packageRoots)
if ($LASTEXITCODE -ne 0 -or $changedPackagePaths.Count -gt 0) {
  throw "Package-visible paths changed after immutable C7 package source: $($changedPackagePaths -join ', ')"
}
if ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ne [string]$modern.package_source_sha256) {
  throw "Current package roots do not reproduce the canonical C7 package-source identity."
}
$candidatePath = Join-Path $repo ([string]$modern.archive)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$candidateZip = [IO.Compression.ZipFile]::OpenRead($candidatePath)
try { $candidateEntries = @($candidateZip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count } finally { $candidateZip.Dispose() }
if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf) -or
    (Get-Item -LiteralPath $candidatePath).Length -ne [long]$modern.archive_bytes -or
    $candidateEntries -ne [int]$modern.archive_entries -or
    (Get-MIRFileSha256 -Path $candidatePath) -ne [string]$modern.archive_sha256 -or
    (Get-MIRZipContentFingerprint -Path $candidatePath) -ne [string]$modern.package_content_sha256) {
  throw "Canonical C7 archive no longer matches its immutable authority row."
}
$superseded = $modern.supersedes_candidate
if ([string]$superseded.candidate_id -ne "C6" -or [long]$superseded.archive_bytes -ne 942170 -or
    [int]$superseded.archive_entries -ne 231 -or
    [string]$superseded.archive_sha256 -ne "CDAA5A6ECB190C81C3DD9069A27D639C670EB0A6DAF56103871920A361CCF3E8" -or
    [string]$superseded.package_content_sha256 -ne "7A0BCB4E1C1DCFE77CDCEEC33CB5B3F03E38E821E05527BA8FE78A0CC50D2B91" -or
    [string]$superseded.package_source_commit -ne "ecb8b0545d3cef1badf1b46a9b4c2170cf0aceee" -or
    [string]$superseded.package_source_tree -ne "420b4315861214fd4275a62106cbaef834e5ff02" -or
    [string]$superseded.package_source_sha256 -ne "7A0BCB4E1C1DCFE77CDCEEC33CB5B3F03E38E821E05527BA8FE78A0CC50D2B91") {
  throw "C7 must retain the complete immutable C6 authority as its superseded candidate."
}
$delta = Read-MIRText ".mir/evidence/3.2.0-c6-to-c7-delta.json" | ConvertFrom-Json
if ([int]$delta.schema -ne 1 -or [string]$delta.record_type -ne "MIRCandidateArchiveDelta" -or [string]$delta.status -ne "PASS" -or
    [string]$delta.baseline.archive_sha256 -ne [string]$superseded.archive_sha256 -or
    [string]$delta.candidate.archive_sha256 -ne [string]$modern.archive_sha256 -or
    [int]$delta.summary.added -ne 25 -or [int]$delta.summary.changed -ne 24 -or [int]$delta.summary.removed -ne 0 -or
    [int]$delta.summary.unchanged -ne 207 -or [int]$delta.summary.unexpected -ne 0) {
  throw "Tracked C6-to-C7 archive delta does not match the two immutable candidate authorities."
}
if ([string]$backport.mir_version -ne "2.5.0" -or [string]$backport.branch -ne "tmp/2.0" -or
    [string]$backport.status -ne "planned-after-3.2-freeze" -or $null -ne $backport.archive) {
  throw "Canonical Factorio 2.0 backport must remain unbuilt MIR 2.5.0 after the 3.2 source freeze."
}

$branches = Read-MIRText ".mir/branches.yml"
$releaseWave = Read-MIRText ".mir/release-wave.yml"
$todo = Read-MIRText "todo.md"
$promotion = Read-MIRText ".github/workflows/assurance-promotion.yml"
foreach ($required in @(
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?m)^\s*dev:\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='MIR 3\.2\.0'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*candidate_id:\s*C7\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?m)^\s*archive_sha256:\s*1E3CC8016A9DA8F399D01BA6B515DD8CF6D414525F99CC08B08278A077FF8B4B\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?m)^\s*package_source_commit:\s*b532e91a227cc4b17526edbb1388c7836e0a6dbe\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='tmp/2\.0'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*mir_3_2_0:\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*candidate_id:\s*C7\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*archive_sha256:\s*1E3CC8016A9DA8F399D01BA6B515DD8CF6D414525F99CC08B08278A077FF8B4B\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*package_source_commit:\s*b532e91a227cc4b17526edbb1388c7836e0a6dbe\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*mir_2_5_0:\s*$'},
  @{Path="todo.md"; Text=$todo; Pattern='MIR 3\.2\.0 verifier hardening'},
  @{Path="todo.md"; Text=$todo; Pattern='bounded C7 architectural convergence from the unqualified C6 foundation'},
  @{Path=".github/workflows/assurance-promotion.yml"; Text=$promotion; Pattern='mir-3\.2\.0-factorio-2\.1\.json'}
)) {
  if ([string]$required.Text -notmatch [string]$required.Pattern) {
    throw "$($required.Path) disagrees with .mir/releases.json."
  }
}
if ($todo -match 'MIR 3\.2 work is not authorized|Start no MIR 3\.2 implementation') {
  throw "todo.md still contains a stale prohibition on authorized MIR 3.2 work."
}

$distributions = Read-MIRText ".mir/distributions.json" | ConvertFrom-Json
$distributionRows = @($distributions.distributions)
if ([int]$distributions.distribution_count -ne $distributionRows.Count) {
  throw "Distribution count differs from the canonical distribution rows."
}
foreach ($forbiddenVersion in @("1.9.5", "2.5.0")) {
  if (@($distributionRows | Where-Object { [string]$_.version -eq $forbiddenVersion }).Count -gt 0) {
    throw "Nonexistent or not-yet-built version $forbiddenVersion must not appear in the tracked distribution inventory."
  }
}
$candidateRows = @($distributionRows | Where-Object { [string]$_.version -eq "3.2.0" })
if ($candidateRows.Count -ne 1 -or [string]$candidateRows[0].kind -ne "development-candidate" -or
    [string]$candidateRows[0].path -ne [string]$modern.archive -or
    [long]$candidateRows[0].bytes -ne [long]$modern.archive_bytes -or
    [string]$candidateRows[0].sha256 -ne [string]$modern.archive_sha256 -or
    [string]$candidateRows[0].source_ref -ne [string]$modern.package_source_commit) {
  throw "The tracked MIR 3.2.0 development distribution must exactly mirror canonical candidate authority."
}

Write-Host "[ok] canonical release ledger and branch, wave, distribution, queue, and promotion views agree."
