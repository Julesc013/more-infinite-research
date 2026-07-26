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
if ([string]$publishedModern.mir_version -ne "3.2.0" -or [string]$publishedModern.tag -ne "3.2.0" -or
    [string]$publishedModern.tag_commit -ne "c8f3d8248cc89b8636cf1ee485fd8889422c6124" -or
    [string]$publishedModern.archive_sha256 -ne "35372EE6D16DA6765E8C30AEAAF5DA4A5D300F02C0A0A03648C80893A5394F32" -or
    [string]$publishedModern.status -ne "published-frozen") {
  throw "Canonical Factorio 2.1 published baseline must remain immutable MIR 3.2.0."
}
if ([string]$publishedBackport.mir_version -ne "2.4.9" -or [string]$publishedBackport.tag -ne "2.4.9" -or
    [string]$publishedBackport.archive -ne "dist/more-infinite-research_2.4.9.zip" -or
    [string]$publishedBackport.status -ne "published-frozen") {
  throw "Canonical Factorio 2.0 published baseline must remain immutable MIR 2.4.9."
}
if ([string]$modern.mir_version -ne "3.2.1" -or [string]$modern.candidate_id -ne "C21" -or
    [string]$modern.branch -ne "main" -or [string]$modern.development_branch -ne "dev" -or
    [string]$modern.archive_class -ne "mod-portal-published-github-release-candidate" -or
    [string]$modern.approved_delta -ne "bounded-c20-to-c21-hotfix-reviewed" -or
    [string]$modern.manual_review -ne "maintainer-playtest-approved" -or
    [string]$modern.publication_status -ne "published-mod-portal-github-pending") {
  throw "Canonical modern release must bind exact MIR 3.2.1 C21 for main promotion."
}
$allowedQualifications = @("focused-emergency-build-passed-full-validation-pending", "full-local-no-reuse-validation-passed")
$allowedStatuses = @("c21-focused-passed-full-validation-pending", "c21-full-local-validation-passed-tag-ready")
if ([string]$modern.qualification -notin $allowedQualifications -or [string]$modern.status -notin $allowedStatuses) {
  throw "Canonical C21 qualification status is not an allowed pre-tag state."
}
if ([string]$modern.release_decision.decision -ne "maintainer-published-mod-portal-emergency-hotfix-before-full-validation" -or
    [string]$modern.release_decision.recorded_at -ne "2026-07-26" -or
    [string]$modern.release_decision.package_delta_from_c20 -ne "planet-space-location-target-resolution-only" -or
    [string]$modern.release_decision.focused_validation -ne "passed" -or
    [string]$modern.release_decision.mod_portal -ne "published-3.2.1" -or
    [string]$modern.release_decision.github_release -ne "pending-tag-after-green-validation" -or
    [string]$modern.release_decision.artifact_rule -ne "publish-the-recorded-zip-without-rebuilding") {
  throw "Canonical C21 emergency publication decision changed."
}
$c21Authority = [ordered]@{
  candidate_id = "C21"
  archive = "dist/more-infinite-research_3.2.1.zip"
  archive_bytes = 1029716
  archive_entries = 290
  package_source_commit = "f3f8cabd0f84be674d5cc190343a9b7df5ba65c5"
  package_source_tree = "f3ba606fb152fbf07951f8af52da129c819f0672"
  package_source_sha256 = "5C6621B2C7A55780EC6F1FB26B1C1FB7B2E88A34604FC997D8A87FE189381188"
  archive_sha256 = "4CE24BE8550CB76EADC2B076747277025E9FD3E7BAAE3E4A996EDD36F78005A6"
  package_content_sha256 = "5C6621B2C7A55780EC6F1FB26B1C1FB7B2E88A34604FC997D8A87FE189381188"
}
foreach ($field in $c21Authority.Keys) {
  if ([string]$modern.$field -ne [string]$c21Authority[$field]) { throw "Canonical C21 authority field '$field' changed." }
}
if ([int]$modern.package_source_material.schema -ne 1 -or
    [string]$modern.package_source_material.hash_algorithm -ne "git-commit-normalized-package-v1" -or
    [string]$modern.package_source_material.source_tree -ne [string]$modern.package_source_tree -or
    [int]$modern.package_source_material.file_count -ne 290) {
  throw "Canonical C21 package-source material must bind its clean source tree and 290 package files."
}
& git -C $repo merge-base --is-ancestor ([string]$modern.package_source_commit) HEAD
if ($LASTEXITCODE -ne 0) { throw "C21 package-source commit is not an ancestor of release-engineering HEAD." }
$packageSourceTree = @(& git -C $repo show -s --format=%T ([string]$modern.package_source_commit))
if ($LASTEXITCODE -ne 0 -or $packageSourceTree.Count -ne 1 -or [string]$packageSourceTree[0] -ne [string]$modern.package_source_tree) { throw "C21 package-source tree does not match canonical authority." }
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
$packageRoots = @(Get-MIRPackageSourceRoots)
$changedPackagePaths = @(& git -C $repo diff --name-only ([string]$modern.package_source_commit) HEAD -- @packageRoots)
if ($LASTEXITCODE -ne 0 -or $changedPackagePaths.Count -gt 0) { throw "Package-visible paths changed after immutable C21 package source: $($changedPackagePaths -join ', ')" }
if ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ne [string]$modern.package_source_sha256) { throw "Current package roots do not reproduce canonical C21 content." }
$candidatePath = Join-Path $repo ([string]$modern.archive)
if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { throw "Canonical C21 archive is missing." }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$candidateZip = [IO.Compression.ZipFile]::OpenRead($candidatePath)
try { $candidateEntries = @($candidateZip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count } finally { $candidateZip.Dispose() }
if ((Get-Item -LiteralPath $candidatePath).Length -ne [long]$modern.archive_bytes -or
    $candidateEntries -ne [int]$modern.archive_entries -or
    (Get-MIRFileSha256 -Path $candidatePath) -ne [string]$modern.archive_sha256 -or
    (Get-MIRZipContentFingerprint -Path $candidatePath) -ne [string]$modern.package_content_sha256) { throw "Canonical C21 archive no longer matches authority." }
$superseded = $modern.supersedes_candidate
if ([string]$superseded.candidate_id -ne "C20" -or [long]$superseded.archive_bytes -ne 1029464 -or
    [int]$superseded.archive_entries -ne 290 -or
    [string]$superseded.archive_sha256 -ne "35372EE6D16DA6765E8C30AEAAF5DA4A5D300F02C0A0A03648C80893A5394F32" -or
    [string]$superseded.package_content_sha256 -ne "26CBE7A12FA30C3352343B77A0062FE07426284992EFCBA8DCB82C221CE2DD18" -or
    [string]$superseded.package_source_commit -ne "303de261629149af5f50bd210368e61423f1a299" -or
    [string]$superseded.package_source_tree -ne "cf60e2adab3c61364b94f192b886845e0c3c0642" -or
    [string]$superseded.package_source_sha256 -ne "26CBE7A12FA30C3352343B77A0062FE07426284992EFCBA8DCB82C221CE2DD18" -or
    [string]$superseded.tag -ne "3.2.0" -or [string]$superseded.status -ne "published-frozen") { throw "C21 must retain complete immutable C20 authority." }if ([string]$backport.mir_version -ne "2.5.0" -or [string]$backport.branch -ne "tmp/2.0" -or
    [string]$backport.source_anchor -ne "3.2.1-final-source-freeze" -or
    [string]$backport.status -ne "backport-in-progress-from-3.2.1" -or $null -ne $backport.archive) {
  throw "Canonical Factorio 2.0 backport must remain in progress from final 3.2.1 source until target authority is committed."
}
$branches = Read-MIRText ".mir/branches.yml"
$releaseWave = Read-MIRText ".mir/release-wave.yml"
$todo = Read-MIRText "todo.md"
$promotion = Read-MIRText ".github/workflows/assurance-promotion.yml"
foreach ($required in @(
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?m)^\s*dev:\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='MIR 3\.2\.0'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*candidate_id:\s*C20\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*branch:\s*main\s*$.*?^\s*development_branch:\s*dev\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?m)^\s*archive_sha256:\s*35372EE6D16DA6765E8C30AEAAF5DA4A5D300F02C0A0A03648C80893A5394F32\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?m)^\s*package_source_commit:\s*303de261629149af5f50bd210368e61423f1a299\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_1:\s*$.*?^\s*candidate_id:\s*C21\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_1:\s*$.*?^\s*archive_sha256:\s*4CE24BE8550CB76EADC2B076747277025E9FD3E7BAAE3E4A996EDD36F78005A6\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_1:\s*$.*?^\s*package_source_commit:\s*f3f8cabd0f84be674d5cc190343a9b7df5ba65c5\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='tmp/2\.0'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*mir_3_2_0:\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*candidate_id:\s*C20\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?ms)^\s*mir_3_2_0:\s*$.*?^\s*branch:\s*main\s*$.*?^\s*development_branch:\s*dev\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*archive_sha256:\s*35372EE6D16DA6765E8C30AEAAF5DA4A5D300F02C0A0A03648C80893A5394F32\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*package_source_commit:\s*303de261629149af5f50bd210368e61423f1a299\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?ms)^\s*mir_3_2_1:\s*$.*?^\s*candidate_id:\s*C21\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?ms)^\s*mir_3_2_1:\s*$.*?^\s*archive_sha256:\s*4CE24BE8550CB76EADC2B076747277025E9FD3E7BAAE3E4A996EDD36F78005A6\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$releaseWave; Pattern='(?m)^\s*mir_2_5_0:\s*$'},
  @{Path="todo.md"; Text=$todo; Pattern='Exact C20 was tagged and published as MIR 3\.2\.0 from `main`'},
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
  @{Path="todo.md"; Text=$todo; Pattern='Create C20 from C19 by journal-verifying competing technology rewires'},
  @{Path=".github/workflows/assurance-promotion.yml"; Text=$promotion; Pattern='mir-3\.2\.1-factorio-2\.1\.json'}
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
$c20Rows = @($distributionRows | Where-Object { [string]$_.version -eq "3.2.0" })
if ($c20Rows.Count -ne 1 -or [string]$c20Rows[0].kind -ne "tagged" -or
    [string]$c20Rows[0].path -ne [string]$publishedModern.archive -or
    [string]$c20Rows[0].sha256 -ne [string]$publishedModern.archive_sha256 -or
    [string]$c20Rows[0].source_ref -ne "3.2.0") {
  throw "The tracked MIR 3.2.0 tagged distribution must mirror its immutable published baseline."
}
$c21Rows = @($distributionRows | Where-Object { [string]$_.version -eq "3.2.1" })
if ($c21Rows.Count -ne 1 -or [string]$c21Rows[0].kind -ne "mod-portal-published-github-pending" -or
    [string]$c21Rows[0].path -ne [string]$modern.archive -or
    [long]$c21Rows[0].bytes -ne [long]$modern.archive_bytes -or
    [string]$c21Rows[0].sha256 -ne [string]$modern.archive_sha256 -or
    [string]$c21Rows[0].source_ref -ne "dev") {
  throw "The tracked MIR 3.2.1 distribution must exactly mirror C21 authority."
}
Write-Host "[ok] canonical release ledger and branch, wave, distribution, queue, and promotion views agree."
