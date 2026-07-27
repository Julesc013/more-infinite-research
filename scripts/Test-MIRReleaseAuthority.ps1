$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")

function Read-MIRJson([string]$Path) {
  Get-Content -Raw -LiteralPath (Join-Path $repo $Path) | ConvertFrom-Json
}
function Read-MIRText([string]$Path) {
  Get-Content -Raw -LiteralPath (Join-Path $repo $Path)
}
function Assert-MIRField($Object, [string]$Name, $Expected, [string]$Scope) {
  if ([string]$Object.$Name -ne [string]$Expected) {
    throw "$Scope field '$Name' changed. Expected '$Expected', got '$($Object.$Name)'."
  }
}

$ledger = Read-MIRJson ".mir/releases.json"
if ([int]$ledger.schema -ne 1 -or [string]$ledger.authority -ne "canonical-release-ledger") {
  throw "Canonical release ledger schema 1 is required."
}
$publishedModern = $ledger.published_baselines."factorio-2.1"
$publishedBackport = $ledger.published_baselines."factorio-2.0"
$modern = $ledger.development."factorio-2.1"
$backport = $ledger.development."factorio-2.0"

$c21 = [ordered]@{
  mir_version = "3.2.1"
  branch = "main"
  tag = "3.2.1"
  package_source_commit = "f3f8cabd0f84be674d5cc190343a9b7df5ba65c5"
  archive = "dist/more-infinite-research_3.2.1.zip"
  archive_sha256 = "4CE24BE8550CB76EADC2B076747277025E9FD3E7BAAE3E4A996EDD36F78005A6"
  package_content_sha256 = "5C6621B2C7A55780EC6F1FB26B1C1FB7B2E88A34604FC997D8A87FE189381188"
}
foreach ($field in $c21.Keys) { Assert-MIRField $publishedModern $field $c21[$field] "Published C21" }
if ([string]$publishedModern.tag_commit -notmatch '^[0-9a-f]{40}$' -or
    [string]$publishedModern.status -notin @("published-mod-portal-tagged-github-release-pending", "published-frozen")) {
  throw "Published C21 tag/status authority is invalid."
}
if ([string]$publishedBackport.mir_version -ne "2.4.9" -or [string]$publishedBackport.tag -ne "2.4.9" -or
    [string]$publishedBackport.archive -ne "dist/more-infinite-research_2.4.9.zip" -or
    [string]$publishedBackport.status -ne "published-frozen") {
  throw "Canonical Factorio 2.0 baseline must remain immutable MIR 2.4.9."
}

$c22 = [ordered]@{
  mir_version = "3.2.2"
  candidate_id = "C22"
  branch = "main"
  development_branch = "dev"
  source_anchor = "3.2.1"
  archive = "dist/more-infinite-research_3.2.2.zip"
  archive_bytes = 1030828
  archive_entries = 291
  package_source_commit = "7ebe10dd52e34c8df54dc98dbc0f1375a134c4b8"
  package_source_tree = "789069c794d86fbd734475ae2fc6c3555581b0cb"
  package_source_sha256 = "B2E5745CB6ED6F093509B358FDBC8D64D45F0BE3A7439B65A6A8CD8FAD5CD0C4"
  archive_sha256 = "638CF9254915B24824BEA6FD66D420B15CD41876334D32AC2ED5D81136D9A938"
  package_content_sha256 = "B2E5745CB6ED6F093509B358FDBC8D64D45F0BE3A7439B65A6A8CD8FAD5CD0C4"
  approved_delta = "bounded-c21-to-c22-hotfix-reviewed"
}
foreach ($field in $c22.Keys) { Assert-MIRField $modern $field $c22[$field] "Active C22" }
if ([string]$modern.archive_class -ne "unreleased-emergency-hotfix-candidate" -or
    [string]$modern.publication_status -ne "unreleased" -or
    [string]$modern.manual_review -notin @("exact-patch-review-pending", "maintainer-patch-review-approved") -or
    [string]$modern.protected_qualification -notin @("pending", "passed")) {
  throw "Active C22 release-state authority is invalid."
}
if ([string]$modern.qualification -notin @(
      "focused-hotfix-validation-passed-full-validation-pending",
      "full-local-no-reuse-validation-passed",
      "protected-no-reuse-validation-passed") -or
    [string]$modern.status -notin @(
      "c22-focused-passed-full-validation-pending",
      "c22-full-local-validation-passed",
      "c22-protected-validation-passed-tag-ready")) {
  throw "Active C22 qualification status is not an allowed candidate state."
}

& git -C $repo merge-base --is-ancestor ([string]$modern.package_source_commit) HEAD
if ($LASTEXITCODE -ne 0) { throw "C22 package source is not an ancestor of release-engineering HEAD." }
$tree = (& git -C $repo show -s --format=%T ([string]$modern.package_source_commit)).Trim()
if ($LASTEXITCODE -ne 0 -or $tree -ne [string]$modern.package_source_tree) {
  throw "C22 package-source tree differs from authority."
}
$roots = @(Get-MIRPackageSourceRoots)
$changedRoots = @(& git -C $repo diff --name-only ([string]$modern.package_source_commit) HEAD -- @roots)
if ($LASTEXITCODE -ne 0 -or $changedRoots.Count -gt 0) {
  throw "Package-visible paths changed after C22 package source: $($changedRoots -join ', ')"
}
if (Test-MIRPackageSourceGitDirty -RepoRoot $repo) { throw "Package-visible source is dirty." }
if ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ne [string]$modern.package_source_sha256) {
  throw "Current package roots do not reproduce canonical C22 content."
}
$candidatePath = Join-Path $repo ([string]$modern.archive)
if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { throw "Canonical C22 archive is missing." }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($candidatePath)
try { $entryCount = @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count }
finally { $zip.Dispose() }
if ((Get-Item -LiteralPath $candidatePath).Length -ne [long]$modern.archive_bytes -or
    $entryCount -ne [int]$modern.archive_entries -or
    (Get-MIRFileSha256 -Path $candidatePath) -ne [string]$modern.archive_sha256 -or
    (Get-MIRZipContentFingerprint -Path $candidatePath) -ne [string]$modern.package_content_sha256) {
  throw "Canonical C22 archive no longer matches authority."
}

$superseded = $modern.supersedes_candidate
foreach ($field in @("archive_sha256", "package_content_sha256", "package_source_commit")) {
  Assert-MIRField $superseded $field $c21[$field] "C22 superseded C21"
}
if ([string]$superseded.candidate_id -ne "C21" -or [string]$superseded.tag -ne "3.2.1" -or
    [string]$superseded.tag_commit -ne [string]$publishedModern.tag_commit) {
  throw "C22 superseded-candidate authority does not bind the published C21 tag."
}
if ([string]$backport.mir_version -ne "2.5.0" -or [string]$backport.branch -ne "tmp/2.0" -or
    [string]$backport.source_anchor -ne "3.2.2-final-source-freeze" -or
    [string]$backport.status -ne "backport-pending-from-3.2.2" -or $null -ne $backport.archive) {
  throw "Factorio 2.0 backport must remain pending from final C22 until target authority is committed."
}

$branches = Read-MIRText ".mir/branches.yml"
$wave = Read-MIRText ".mir/release-wave.yml"
$todo = Read-MIRText "todo.md"
$requiredViews = @(
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_1:\s*$.*?^\s*candidate_id:\s*C21\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_2:\s*$.*?^\s*candidate_id:\s*C22\s*$'},
  @{Path=".mir/branches.yml"; Text=$branches; Pattern='(?ms)^\s*mir_3_2_2:\s*$.*?^\s*archive_sha256:\s*638CF9254915B24824BEA6FD66D420B15CD41876334D32AC2ED5D81136D9A938\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$wave; Pattern='(?ms)^\s*mir_3_2_1:\s*$.*?^\s*candidate_id:\s*C21\s*$'},
  @{Path=".mir/release-wave.yml"; Text=$wave; Pattern='(?ms)^\s*mir_3_2_2:\s*$.*?^\s*candidate_id:\s*C22\s*$'},
  @{Path="todo.md"; Text=$todo; Pattern='MIR 3\.2\.2'}
)
foreach ($view in $requiredViews) {
  if ([string]$view.Text -notmatch [string]$view.Pattern) { throw "$($view.Path) does not mirror canonical C22/C21 authority." }
}

$distributionRows = @((Read-MIRJson ".mir/distributions.json").distributions)
$c21Rows = @($distributionRows | Where-Object { [string]$_.version -eq "3.2.1" })
$c22Rows = @($distributionRows | Where-Object { [string]$_.version -eq "3.2.2" })
if ($c21Rows.Count -ne 1 -or [string]$c21Rows[0].path -ne [string]$publishedModern.archive -or
    [string]$c21Rows[0].sha256 -ne [string]$publishedModern.archive_sha256 -or [string]$c21Rows[0].source_ref -ne "3.2.1") {
  throw "Distribution inventory does not retain exact tagged C21."
}
if ($c22Rows.Count -ne 1 -or [string]$c22Rows[0].path -ne [string]$modern.archive -or
    [long]$c22Rows[0].bytes -ne [long]$modern.archive_bytes -or [string]$c22Rows[0].sha256 -ne [string]$modern.archive_sha256 -or
    [string]$c22Rows[0].kind -ne "unreleased-emergency-hotfix-candidate" -or [string]$c22Rows[0].source_ref -ne "dev") {
  throw "Distribution inventory does not bind exact unreleased C22."
}
foreach ($forbiddenVersion in @("1.9.5", "2.5.0")) {
  if (@($distributionRows | Where-Object { [string]$_.version -eq $forbiddenVersion }).Count -gt 0) {
    throw "Nonexistent or not-yet-authorized version $forbiddenVersion must not appear in the distribution inventory."
  }
}
Write-Host "[ok] canonical C21 baseline, active C22, branch/wave views, distribution inventory, and C22-anchored backport agree."