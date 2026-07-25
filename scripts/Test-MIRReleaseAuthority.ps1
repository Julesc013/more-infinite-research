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
if ([string]$modern.mir_version -ne "3.2.0" -or [string]$modern.branch -ne "main" -or
    [string]$modern.development_branch -ne "dev" -or
    [string]$modern.archive_class -ne "main-staged-fast-validated-release-candidate" -or
    [string]$modern.qualification -ne "fast-static-deterministic-package-and-release-authority-passed" -or
    [string]$modern.approved_delta -ne "pending" -or
    [string]$modern.upgrade_qualification -ne "pending" -or
    [string]$modern.runtime_qualification -ne "pending" -or
    [string]$modern.manual_review -ne "pending" -or
    [string]$modern.protected_qualification -ne "pending" -or
    [string]$modern.publication_status -ne "staged-on-main-awaiting-long-validation-tag-and-publication" -or
    [string]$modern.status -ne "c19-main-staged-fast-validation-passed-long-validation-pending") {
  throw "Canonical modern release must remain exact MIR 3.2.0 C19 staged on main after fast validation with long validation pending."
}
if ([string]$modern.release_decision.decision -ne "maintainer-directed-fast-stage-then-long-validation-before-tag" -or
    [string]$modern.release_decision.recorded_at -ne "2026-07-25" -or
    [string]$modern.release_decision.package_delta_from_c18 -ne "packaged-changelog-date-only" -or
    [string]$modern.release_decision.fast_validation -ne "passed" -or
    [string]$modern.release_decision.long_validation -ne "pending" -or
    [string]$modern.release_decision.tag -ne "pending" -or
    [string]$modern.release_decision.publication -ne "pending" -or
    [string]$modern.release_decision.artifact_rule -ne "publish-the-recorded-zip-without-rebuilding") {
  throw "Canonical C19 staging decision must require fresh long validation before tag and publication."
}
$c19Authority = [ordered]@{
  candidate_id = "C19"
  archive = "dist/more-infinite-research_3.2.0.zip"
  archive_bytes = 1026920
  archive_entries = 290
  package_source_commit = "62c084dcd6fb5650ac67abcaa50a08ced218b87c"
  package_source_tree = "0746dc2bce8c4feac0d0f7d6dbdc8d6ffa105d3d"
  package_source_sha256 = "4D5D05A0225D3F2AA322EC418A8975BF48C949B4AC2B053B4956B5EE217641D0"
  archive_sha256 = "6592D46C2F3F293770A69C21A59A4CB7A9012D759F2E6D078E62F26BA9BBA6C6"
  package_content_sha256 = "4D5D05A0225D3F2AA322EC418A8975BF48C949B4AC2B053B4956B5EE217641D0"
}
foreach ($field in $c19Authority.Keys) {
  if ([string]$modern.$field -ne [string]$c19Authority[$field]) {
    throw "Canonical C19 authority field '$field' changed. A later candidate is required if candidate bytes change."
  }
}
if ([int]$modern.package_source_material.schema -ne 1 -or
    [string]$modern.package_source_material.hash_algorithm -ne "git-commit-normalized-package-v1" -or
    [string]$modern.package_source_material.source_tree -ne [string]$modern.package_source_tree -or
    [int]$modern.package_source_material.file_count -ne 290) {
  throw "Canonical C19 package-source material descriptor must bind its clean source tree and 290 package files."
}
& git -C $repo merge-base --is-ancestor ([string]$modern.package_source_commit) HEAD
if ($LASTEXITCODE -ne 0) { throw "C19 package-source commit is not an ancestor of release-engineering HEAD." }
$packageSourceTree = @(& git -C $repo rev-parse "$([string]$modern.package_source_commit)^{tree}")
if ($LASTEXITCODE -ne 0 -or $packageSourceTree.Count -ne 1 -or [string]$packageSourceTree[0] -ne [string]$modern.package_source_tree) {
  throw "C19 package-source tree does not match the canonical authority row."
}
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
$packageRoots = @(Get-MIRPackageSourceRoots)
$changedPackagePaths = @(& git -C $repo diff --name-only ([string]$modern.package_source_commit) HEAD -- @packageRoots)
if ($LASTEXITCODE -ne 0 -or $changedPackagePaths.Count -gt 0) {
  throw "Package-visible paths changed after immutable C19 package source: $($changedPackagePaths -join ', ')"
}
if ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ne [string]$modern.package_source_sha256) {
  throw "Current package roots do not reproduce the canonical C19 package-source identity."
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
  throw "Canonical C19 archive no longer matches its immutable authority row."
}
$superseded = $modern.supersedes_candidate
if ([string]$superseded.candidate_id -ne "C18" -or [long]$superseded.archive_bytes -ne 1026915 -or
    [int]$superseded.archive_entries -ne 290 -or
    [string]$superseded.archive_sha256 -ne "C3F51041733A79AAE24D3882FC9FF63227A1455C6D63376B2DDE9858DC30520E" -or
    [string]$superseded.package_content_sha256 -ne "1CDCBE41F644DB187153165617835FB8008DD69767A9BD6C78B396E8160065F5" -or
    [string]$superseded.package_source_commit -ne "55a57548316729d89482c96dcecd7c65f26c6103" -or
    [string]$superseded.package_source_tree -ne "958aae2feeea0a3f6a3a4c1cffc431985c9537a4" -or
    [string]$superseded.package_source_sha256 -ne "1CDCBE41F644DB187153165617835FB8008DD69767A9BD6C78B396E8160065F5") {
  throw "C19 must retain the complete immutable C18 authority as its superseded candidate."
}
if ([string]$backport.mir_version -ne "2.5.0" -or [string]$backport.branch -ne "tmp/2.0" -or
    [string]$backport.source_anchor -ne "3.2.5-final-source-freeze" -or
    [string]$backport.status -ne "planned-after-3.2.5-freeze" -or $null -ne $backport.archive) {
  throw "Canonical Factorio 2.0 backport must remain unbuilt MIR 2.5.0 after the final 3.2.5 source freeze."
}

$branches = Read-MIRText ".mir/branches.yml"
$releaseWave = Read-MIRText ".mir/release-wave.yml"
$todo = Read-MIRText "todo.md"
$promotion = Read-MIRText ".github/workflows/assurance-promotion.yml"
foreach ($required in @(
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?m)^\s*dev:\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='MIR 3\.2\.0'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*candidate_id:\s*C19\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*branch:\s*main\s*$.*?^\s*development_branch:\s*dev\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?m)^\s*archive_sha256:\s*6592D46C2F3F293770A69C21A59A4CB7A9012D759F2E6D078E62F26BA9BBA6C6\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?m)^\s*package_source_commit:\s*62c084dcd6fb5650ac67abcaa50a08ced218b87c\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='tmp/2\.0'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*mir_3_2_0:\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*candidate_id:\s*C19\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*branch:\s*main\s*$.*?^\s*development_branch:\s*dev\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*archive_sha256:\s*6592D46C2F3F293770A69C21A59A4CB7A9012D759F2E6D078E62F26BA9BBA6C6\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*package_source_commit:\s*62c084dcd6fb5650ac67abcaa50a08ced218b87c\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*mir_2_5_0:\s*$'},
  @{Path="todo.md"; Text=$todo; Pattern='Exact C19 is staged on `main` for the MIR 3\.2\.0 tag and publication'},
  @{Path="todo.md"; Text=$todo; Pattern='governed C10 compiler contract-closure overhaul from the unqualified C9 foundation'},
  @{Path="todo.md"; Text=$todo; Pattern='exact-singleton candidate-seed ambiguity defect as C11'},
  @{Path="todo.md"; Text=$todo; Pattern='freeze C12 without widening the technology set'},
  @{Path="todo.md"; Text=$todo; Pattern='freeze exact C13 without changing technology identities or selections'},
  @{Path="todo.md"; Text=$todo; Pattern='Replace C13 with exact C14 after full static qualification'},
  @{Path="todo.md"; Text=$todo; Pattern='Replace C14 with exact C15 after the K2SO science-progression playtest defect'},
  @{Path="todo.md"; Text=$todo; Pattern='Replace rejected C15 with exact C16 after the fixed-cost compiler performance correction'},
  @{Path="todo.md"; Text=$todo; Pattern='Create C17 from C16 by enabling every shipped technology toggle by default'},
  @{Path="todo.md"; Text=$todo; Pattern='Create C18 from C17 with bounded Space Age productivity streams'},
  @{Path="todo.md"; Text=$todo; Pattern='Create C19 from C18 by adding the final packaged changelog date'},
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
if ($candidateRows.Count -ne 1 -or [string]$candidateRows[0].kind -ne "release-staged-fast-validated-candidate" -or
    [string]$candidateRows[0].path -ne [string]$modern.archive -or
    [long]$candidateRows[0].bytes -ne [long]$modern.archive_bytes -or
    [string]$candidateRows[0].sha256 -ne [string]$modern.archive_sha256 -or
    [string]$candidateRows[0].source_ref -ne [string]$modern.package_source_commit) {
  throw "The tracked MIR 3.2.0 release-staged distribution must exactly mirror canonical candidate authority."
}

Write-Host "[ok] canonical release ledger and branch, wave, distribution, queue, and promotion views agree."
