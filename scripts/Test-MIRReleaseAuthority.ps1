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
$info = Read-MIRText "info.json" | ConvertFrom-Json
if ([string]$info.factorio_version -eq "2.0") {
  if ([string]$info.version -ne "2.5.0" -or [string]$backport.mir_version -ne "2.5.0" -or
      [string]$backport.branch -ne "tmp/2.0" -or [string]$backport.candidate_id -notmatch '^2\.5-P[0-9]+$' -or
      [string]$backport.archive_class -ne "automated-playtest-candidate" -or
      [string]$backport.manual_review -notlike "pending*" -or [string]$backport.protected_qualification -notlike "pending*" -or
      [string]$backport.publication_status -ne "unreleased" -or
      [string]$backport.status -notmatch '^automated-playtest-candidate-') {
    throw "Factorio 2.0 authority must describe an unreleased automated playtest candidate with manual and protected qualification pending."
  }
  if ([string]$backport.portable_source_commit -ne "c1fd8b932c8d916a14925678056e08893b87b2db") {
    throw "The 2.5 portable source must bind the exact tagged C30 package-source commit."
  }
  foreach ($commitField in @("portable_source_commit", "package_source_commit")) {
    $commit = [string]$backport.$commitField
    if ($commit -notmatch '^[0-9a-f]{40}$') { throw "2.5 $commitField must be a full lowercase Git commit." }
    & git -C $repo cat-file -e "$commit`^{commit}"
    if ($LASTEXITCODE -ne 0) { throw "2.5 $commitField is unavailable: $commit" }
  }
  & git -C $repo merge-base --is-ancestor ([string]$publishedBackport.tag_commit) HEAD
  if ($LASTEXITCODE -ne 0) { throw "The provisional 2.5 line is not descended from immutable 2.4.9." }
  $sourceLock = Read-MIRText ".mir/backport-source-lock.json" | ConvertFrom-Json
  if ([int]$sourceLock.schema -ne 4 -or [string]$sourceLock.portable_source.commit -ne [string]$backport.portable_source_commit -or
      [string]$sourceLock.projection.package_source_commit -ne [string]$backport.package_source_commit -or
      [string]$sourceLock.projection.portable_delta_ledger -ne [string]$backport.portable_delta_ledger) {
    throw "The 2.5 release ledger and exact C30 portable source lock disagree."
  }
  & git -C $repo merge-base --is-ancestor ([string]$backport.package_source_commit) HEAD
  if ($LASTEXITCODE -ne 0) { throw "The provisional 2.5 package-source commit is not an ancestor of qualification HEAD." }

  . (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
  $packageRoots = @(Get-MIRPackageSourceRoots)
  $packageChanges = @(& git -C $repo diff --name-only ([string]$backport.package_source_commit) HEAD -- @packageRoots)
  if ($LASTEXITCODE -ne 0 -or $packageChanges.Count -gt 0) {
    throw "Package-visible paths changed after provisional 2.5 package source: $($packageChanges -join ', ')"
  }
  $sourceTree = @(& git -C $repo rev-parse "$([string]$backport.package_source_commit)^{tree}")
  if ($LASTEXITCODE -ne 0 -or $sourceTree.Count -ne 1 -or [string]$sourceTree[0] -ne [string]$backport.package_source_tree -or
      [string]$backport.package_source_material.source_tree -ne [string]$backport.package_source_tree -or
      [string]$backport.package_source_material.hash_algorithm -ne "git-commit-normalized-package-v1") {
    throw "The provisional 2.5 clean package-source tree/material descriptor is invalid."
  }
  if ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ne [string]$backport.package_source_sha256) {
    throw "Current package roots do not reproduce provisional 2.5 package-source identity."
  }
  $candidatePath = Join-Path $repo ([string]$backport.archive)
  if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { throw "Provisional 2.5 archive is absent." }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $candidateZip = [IO.Compression.ZipFile]::OpenRead($candidatePath)
  try { $candidateEntries = @($candidateZip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count } finally { $candidateZip.Dispose() }
  if ((Get-Item -LiteralPath $candidatePath).Length -ne [long]$backport.archive_bytes -or
      $candidateEntries -ne [int]$backport.archive_entries -or
      (Get-MIRFileSha256 -Path $candidatePath) -ne [string]$backport.archive_sha256 -or
      (Get-MIRZipContentFingerprint -Path $candidatePath) -ne [string]$backport.package_content_sha256) {
    throw "Provisional 2.5 archive no longer matches canonical candidate authority."
  }

  $distributions = Read-MIRText ".mir/distributions.json" | ConvertFrom-Json
  $distributionRows = @($distributions.distributions)
  $candidateRows = @($distributionRows | Where-Object { [string]$_.version -eq "2.5.0" })
  if ([int]$distributions.distribution_count -ne $distributionRows.Count -or $candidateRows.Count -ne 1 -or
      [string]$candidateRows[0].kind -ne "automated-playtest-candidate" -or
      [string]$candidateRows[0].path -ne [string]$backport.archive -or
      [long]$candidateRows[0].bytes -ne [long]$backport.archive_bytes -or
      [string]$candidateRows[0].sha256 -ne [string]$backport.archive_sha256 -or
      [string]$candidateRows[0].source_ref -ne [string]$backport.package_source_commit) {
    throw "Tracked 2.5.0 distribution must exactly mirror provisional candidate authority."
  }
  $releaseWave = Read-MIRText ".mir/release-wave.yml"
  foreach ($value in @($backport.candidate_id, $backport.package_source_commit, $backport.archive_sha256, $backport.package_content_sha256)) {
    if (-not $releaseWave.Contains([string]$value)) { throw "2.5 release-wave view omits canonical value $value" }
  }
  Write-Host "[ok] provisional MIR 2.5 release, package-source, distribution, and pending-gate authorities agree."
  return
}
if ([string]$modern.mir_version -ne "3.2.0" -or [string]$modern.branch -ne "dev" -or
    [string]$modern.qualification -ne "focused-automation-passed-full-no-reuse-pending") {
  throw "Canonical modern development release must remain MIR 3.2.0 C16 on dev with full no-reuse qualification pending."
}
$c16Authority = [ordered]@{
  candidate_id = "C16"
  archive = "dist/more-infinite-research_3.2.0.zip"
  archive_bytes = 1014593
  archive_entries = 288
  package_source_commit = "0448ceb8d3992082718e2df83bd6a42c56955636"
  package_source_tree = "eb6a5b42676ab65bb95ee7c1422f2191730b1338"
  package_source_sha256 = "10BB848EA5899873C42CDF29F676806BC8BE282C2A4BFC09CE760E72331714A7"
  archive_sha256 = "4646277AC8FBC67D453EAAAEE13C3167630AD94BFE490AD08D592844B6D7B38D"
  package_content_sha256 = "10BB848EA5899873C42CDF29F676806BC8BE282C2A4BFC09CE760E72331714A7"
}
foreach ($field in $c16Authority.Keys) {
  if ([string]$modern.$field -ne [string]$c16Authority[$field]) {
    throw "Canonical C16 authority field '$field' changed. A later candidate is required if candidate bytes change."
  }
}
if ([int]$modern.package_source_material.schema -ne 1 -or
    [string]$modern.package_source_material.hash_algorithm -ne "git-commit-normalized-package-v1" -or
    [string]$modern.package_source_material.source_tree -ne [string]$modern.package_source_tree -or
    [int]$modern.package_source_material.file_count -ne 288) {
  throw "Canonical C16 package-source material descriptor must bind its clean source tree and 288 package files."
}
& git -C $repo merge-base --is-ancestor ([string]$modern.package_source_commit) HEAD
if ($LASTEXITCODE -ne 0) { throw "C16 package-source commit is not an ancestor of release-engineering HEAD." }
$packageSourceTree = @(& git -C $repo rev-parse "$([string]$modern.package_source_commit)^{tree}")
if ($LASTEXITCODE -ne 0 -or $packageSourceTree.Count -ne 1 -or [string]$packageSourceTree[0] -ne [string]$modern.package_source_tree) {
  throw "C16 package-source tree does not match the canonical authority row."
}
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
$packageRoots = @(Get-MIRPackageSourceRoots)
$changedPackagePaths = @(& git -C $repo diff --name-only ([string]$modern.package_source_commit) HEAD -- @packageRoots)
if ($LASTEXITCODE -ne 0 -or $changedPackagePaths.Count -gt 0) {
  throw "Package-visible paths changed after immutable C16 package source: $($changedPackagePaths -join ', ')"
}
if ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ne [string]$modern.package_source_sha256) {
  throw "Current package roots do not reproduce the canonical C16 package-source identity."
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
  throw "Canonical C16 archive no longer matches its immutable authority row."
}
$superseded = $modern.supersedes_candidate
if ([string]$superseded.candidate_id -ne "C15" -or [long]$superseded.archive_bytes -ne 1000692 -or
    [int]$superseded.archive_entries -ne 286 -or
    [string]$superseded.archive_sha256 -ne "89158F34FF5C46C133A832E15AB6872925F87A481C49457DEBD61D1B808CBFAA" -or
    [string]$superseded.package_content_sha256 -ne "E7729822E79265E2C2BE49353755883B145CEE8413F99A00C62CBA6EDAA80242" -or
    [string]$superseded.package_source_commit -ne "c3a56e88fa15da7c12db3b0d11c3d4e732935746" -or
    [string]$superseded.package_source_tree -ne "de885bb52a10a6ee44517a8efda84be629019c28" -or
    [string]$superseded.package_source_sha256 -ne "E7729822E79265E2C2BE49353755883B145CEE8413F99A00C62CBA6EDAA80242") {
  throw "C16 must retain the complete immutable C15 authority as its superseded candidate."
}
$delta = Read-MIRText ".mir/evidence/3.2.0-c15-to-c16-delta.json" | ConvertFrom-Json
if ([int]$delta.schema -ne 1 -or [string]$delta.record_type -ne "MIRCandidateArchiveDelta" -or [string]$delta.status -ne "PASS" -or
    [string]$delta.baseline.archive_sha256 -ne [string]$superseded.archive_sha256 -or
    [string]$delta.candidate.archive_sha256 -ne [string]$modern.archive_sha256 -or
    [int]$delta.summary.added -ne 2 -or [int]$delta.summary.changed -ne 38 -or [int]$delta.summary.removed -ne 0 -or
    [int]$delta.summary.unchanged -ne 248 -or [int]$delta.summary.unexpected -ne 0) {
  throw "Tracked C15-to-C16 archive delta does not match the two immutable candidate authorities."
}
$deltaPaths = @($delta.changes | ForEach-Object { [string]$_.path } | Sort-Object)
if (@($deltaPaths | Where-Object { $_ -notlike "prototypes/mir/*" }).Count -ne 0 -or
    @($delta.changes | Where-Object { -not [bool]$_.allowed -or [string]$_.change -eq "removed" }).Count -ne 0) {
  throw "C15-to-C16 delta must contain only additive or changed compiler implementation files under prototypes/mir/."
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
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*candidate_id:\s*C16\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?m)^\s*archive_sha256:\s*4646277AC8FBC67D453EAAAEE13C3167630AD94BFE490AD08D592844B6D7B38D\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?m)^\s*package_source_commit:\s*0448ceb8d3992082718e2df83bd6a42c56955636\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='tmp/2\.0'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*mir_3_2_0:\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*candidate_id:\s*C16\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*archive_sha256:\s*4646277AC8FBC67D453EAAAEE13C3167630AD94BFE490AD08D592844B6D7B38D\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*package_source_commit:\s*0448ceb8d3992082718e2df83bd6a42c56955636\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*mir_2_5_0:\s*$'},
  @{Path="todo.md"; Text=$todo; Pattern='MIR 3\.2\.0 verifier hardening'},
  @{Path="todo.md"; Text=$todo; Pattern='governed C10 compiler contract-closure overhaul from the unqualified C9 foundation'},
  @{Path="todo.md"; Text=$todo; Pattern='exact-singleton candidate-seed ambiguity defect as C11'},
  @{Path="todo.md"; Text=$todo; Pattern='freeze C12 without widening the technology set'},
  @{Path="todo.md"; Text=$todo; Pattern='freeze exact C13 without changing technology identities or selections'},
  @{Path="todo.md"; Text=$todo; Pattern='Replace C13 with exact C14 after full static qualification'},
  @{Path="todo.md"; Text=$todo; Pattern='Replace C14 with exact C15 after the K2SO science-progression playtest defect'},
  @{Path="todo.md"; Text=$todo; Pattern='Replace rejected C15 with exact C16 after the fixed-cost compiler performance correction'},
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
if ($candidateRows.Count -ne 1 -or [string]$candidateRows[0].kind -ne "automated-playtest-candidate" -or
    [string]$candidateRows[0].path -ne [string]$modern.archive -or
    [long]$candidateRows[0].bytes -ne [long]$modern.archive_bytes -or
    [string]$candidateRows[0].sha256 -ne [string]$modern.archive_sha256 -or
    [string]$candidateRows[0].source_ref -ne [string]$modern.package_source_commit) {
  throw "The tracked MIR 3.2.0 development distribution must exactly mirror canonical candidate authority."
}

Write-Host "[ok] canonical release ledger and branch, wave, distribution, queue, and promotion views agree."
