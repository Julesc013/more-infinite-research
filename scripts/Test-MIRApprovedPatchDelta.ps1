param(
  [string]$Path = "approved-delta\3.2.1-to-3.2.2.json",
  [string]$Candidate = "dist\more-infinite-research_3.2.2.zip",
  [string]$ExpectedSourceCommit = "",
  [switch]$ValidateStructureOnly
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Resolve-MIRPatchPath([string]$Value) {
  if ([IO.Path]::IsPathRooted($Value)) { return [IO.Path]::GetFullPath($Value) }
  return [IO.Path]::GetFullPath((Join-Path $repo $Value))
}

function Get-MIRPatchEntries([string]$ZipPath) {
  $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $result = @{}
    foreach ($entry in $archive.Entries) {
      if ([string]::IsNullOrEmpty($entry.Name)) { continue }
      $parts = $entry.FullName.Replace('\', '/').Split('/', 2)
      if ($parts.Count -ne 2) { throw "Package entry has no versioned root: $($entry.FullName)" }
      $stream = $entry.Open()
      $sha = [Security.Cryptography.SHA256]::Create()
      try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
      finally { $sha.Dispose(); $stream.Dispose() }
      $result[$parts[1]] = $hash
    }
    return $result
  }
  finally { $archive.Dispose() }
}

$artifactPath = Resolve-MIRPatchPath $Path
$artifact = Get-Content -Raw -LiteralPath $artifactPath | ConvertFrom-Json
if ([int]$artifact.schema -ne 1 -or [string]$artifact.kind -ne "mir-approved-patch-delta" -or [string]$artifact.status -ne "approved") {
  throw "Approved patch delta must be an approved schema-1 mir-approved-patch-delta."
}
$baselinePath = Resolve-MIRPatchPath ([string]$artifact.baseline.archive)
$candidatePath = Resolve-MIRPatchPath $Candidate
foreach ($pathValue in @($baselinePath, $candidatePath)) {
  if (-not (Test-Path -LiteralPath $pathValue -PathType Leaf)) { throw "Patch-delta archive is missing: $pathValue" }
}
if ([string]$artifact.baseline.version -ne "3.2.1" -or
    [string]$artifact.baseline.archive_sha256 -ne "4CE24BE8550CB76EADC2B076747277025E9FD3E7BAAE3E4A996EDD36F78005A6" -or
    (Get-MIRFileSha256 -Path $baselinePath) -ne [string]$artifact.baseline.archive_sha256 -or
    (Get-MIRZipContentFingerprint -Path $baselinePath) -ne [string]$artifact.baseline.package_content_sha256) {
  throw "Approved patch baseline is not immutable MIR 3.2.1 C21."
}
$ledger = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\releases.json") | ConvertFrom-Json
$current = $ledger.development."factorio-2.1"
if ([string]$artifact.current.version -ne "3.2.2" -or [string]$current.candidate_id -ne "C24" -or
    [string]$artifact.current.source_commit -ne [string]$current.package_source_commit -or
    [string]$artifact.current.package_source_commit -ne [string]$current.package_source_commit -or
    (Get-MIRFileSha256 -Path $candidatePath) -ne [string]$artifact.current.archive_sha256 -or
    (Get-MIRZipContentFingerprint -Path $candidatePath) -ne [string]$artifact.current.package_content_sha256 -or
    [string]$current.archive_sha256 -ne [string]$artifact.current.archive_sha256 -or
    [string]$current.package_content_sha256 -ne [string]$artifact.current.package_content_sha256) {
  throw "Approved patch current side does not bind exact C24."
}
$baselineEntries = Get-MIRPatchEntries $baselinePath
$currentEntries = Get-MIRPatchEntries $candidatePath
$added = @($currentEntries.Keys | Where-Object { -not $baselineEntries.ContainsKey($_) } | Sort-Object)
$removed = @($baselineEntries.Keys | Where-Object { -not $currentEntries.ContainsKey($_) } | Sort-Object)
$changed = @($currentEntries.Keys | Where-Object { $baselineEntries.ContainsKey($_) -and $baselineEntries[$_] -ne $currentEntries[$_] } | Sort-Object)
$expectedAdded = @($artifact.allowed_added_paths | ForEach-Object { [string]$_ } | Sort-Object)
$expectedChanged = @($artifact.allowed_changed_paths | ForEach-Object { [string]$_ } | Sort-Object)
if ((Compare-Object $expectedAdded $added).Count -ne 0 -or $removed.Count -ne 0 -or
    (Compare-Object $expectedChanged $changed).Count -ne 0) {
  throw "C24 patch delta escaped its exact four-path boundary. Added=$($added -join ',') Removed=$($removed -join ',') Changed=$($changed -join ',')"
}
if ($added.Count -ne 1 -or $added[0] -ne 'prototypes/mir/runtime/planet_discovery_recovery.lua' -or
    $changed.Count -ne 3 -or $changed -notcontains 'changelog.txt' -or
    $changed -notcontains 'info.json' -or
    $changed -notcontains 'prototypes/mir/runtime/scripted_techs.lua') {
  throw "C24 patch delta must add only the recovery handler and change exactly metadata, changelog, and handler registration."
}
if (-not $ValidateStructureOnly) {
  if ([string]::IsNullOrWhiteSpace($ExpectedSourceCommit)) { throw "Exact patch-delta validation requires ExpectedSourceCommit." }
  & git -C $repo merge-base --is-ancestor ([string]$current.package_source_commit) $ExpectedSourceCommit
  if ($LASTEXITCODE -ne 0) { throw "C24 package source is not an ancestor of qualification source." }
  $roots = @(Get-MIRPackageSourceRoots)
  $changes = @(& git -C $repo diff --name-only ([string]$current.package_source_commit) $ExpectedSourceCommit -- @roots)
  if ($LASTEXITCODE -ne 0 -or $changes.Count -gt 0 -or (Test-MIRPackageSourceGitDirty -RepoRoot $repo)) {
    throw "Package-visible source changed after C24 authority: $($changes -join ', ')"
  }
}
Write-Host "[ok] exact MIR 3.2.1 to 3.2.2 approved four-path hotfix delta."