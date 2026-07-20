param(
  [string]$Path = "approved-delta\2.4.5-to-2.4.9.json",
  [string]$Candidate = "dist\more-infinite-research_2.4.9.zip",
  [string]$Baseline = "dist\more-infinite-research_2.4.5.zip",
  [Parameter(Mandatory)][string]$ExpectedSourceCommit
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
function Resolve-MIRDeltaTestPath([string]$Value) {
  if ([IO.Path]::IsPathRooted($Value)) { return [IO.Path]::GetFullPath($Value) }
  return [IO.Path]::GetFullPath((Join-Path $repo $Value))
}
$artifactPath = Resolve-MIRDeltaTestPath $Path
$candidatePath = Resolve-MIRDeltaTestPath $Candidate
$baselinePath = Resolve-MIRDeltaTestPath $Baseline
foreach ($required in @($artifactPath, $candidatePath, $baselinePath)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Approved-delta input is absent: $required" }
}
$artifact = Get-Content -Raw -LiteralPath $artifactPath | ConvertFrom-Json
if ([int]$artifact.schema -ne 2 -or [string]$artifact.kind -ne "mir-approved-package-delta") {
  throw "Approved-delta artifact must use mir-approved-package-delta schema 2."
}
if ([string]$artifact.baseline.version -ne "2.4.5" -or
    [string]$artifact.baseline.archive_sha256 -ne "7649824B72247AA38F05661422DFDEE7C729B21CC73A0A35D2455443B45D39F8" -or
    [string]$artifact.baseline.archive_sha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $baselinePath).Hash -or
    [string]$artifact.baseline.package_content_sha256 -ne (Get-MIRZipContentFingerprint -Path $baselinePath)) {
  throw "Approved-delta artifact does not bind the published MIR 2.4.5 baseline."
}
$candidateSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidatePath).Hash
$candidateContent = Get-MIRZipContentFingerprint -Path $candidatePath
if ([string]$artifact.current.version -ne "2.4.9" -or
    [string]$artifact.current.archive_sha256 -ne $candidateSha -or
    [string]$artifact.current.package_content_sha256 -ne $candidateContent -or
    [string]$artifact.current.source_commit -ne $ExpectedSourceCommit) {
  throw "Approved-delta artifact does not bind the exact MIR 2.4.9 candidate and package source commit."
}
& git -C $repo cat-file -e "$ExpectedSourceCommit`^{commit}"
if ($LASTEXITCODE -ne 0) { throw "Approved-delta package-source commit is unavailable." }
& git -C $repo merge-base --is-ancestor $ExpectedSourceCommit HEAD
if ($LASTEXITCODE -ne 0) { throw "Approved-delta package-source commit is not an ancestor of HEAD." }
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
$roots = @(Get-MIRPackageSourceRoots)
& git -C $repo diff --quiet $ExpectedSourceCommit HEAD -- @roots
if ($LASTEXITCODE -ne 0 -or (Test-MIRPackageSourceGitDirty -RepoRoot $repo)) {
  throw "Package-visible source changed after approved-delta generation."
}
if ($candidateContent -ne (Get-MIRPackageSourceFingerprint -RepoRoot $repo)) {
  throw "Approved-delta candidate content differs from the current package authority."
}
$lock = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\backport-source-lock.json") | ConvertFrom-Json
$declared = @($lock.adapted_package_paths.PSObject.Properties.Name | Sort-Object)
$rows = @($artifact.differences)
$actual = @($rows.path | Sort-Object)
if ((Compare-Object $declared $actual).Count -ne 0 -or @($actual | Group-Object | Where-Object Count -gt 1).Count -ne 0) {
  throw "Approved-delta rows do not equal the declared 2.4.9 package boundary."
}
foreach ($row in $rows) {
  if ([string]$row.change -notin @("added", "changed", "removed") -or $row.intentional -ne $true -or
      [string]::IsNullOrWhiteSpace([string]$row.reason) -or @($row.required_evidence).Count -eq 0) {
    throw "Approved-delta row is incomplete or unapproved: $($row.path)"
  }
}
if ($artifact.invariants.settings_paths_unchanged -ne $true -or
    $artifact.invariants.migration_paths_unchanged -ne $true) {
  throw "Approved-delta violates stable settings or migrations."
}
$streamPaths = @($rows.path | Where-Object {
  $_ -like "prototypes/streams/*" -or $_ -eq "prototypes/mir/streams/generated_stream_manifest.json"
} | Sort-Object -Unique)
$expectedStreamPaths = @(
  "prototypes/mir/streams/generated_stream_manifest.json",
  "prototypes/streams/productivity.lua"
)
if ((Compare-Object $expectedStreamPaths $streamPaths).Count -ne 0 -or
    $artifact.invariants.stream_paths_unchanged -ne $false) {
  throw "Approved-delta stream changes must be exactly the declared steel-productivity definition and manifest."
}
if ([string]$artifact.summary.status -ne "approved" -or [int]$artifact.summary.unapproved_count -ne 0 -or
    [int]$artifact.summary.difference_count -ne $rows.Count -or [int]$artifact.summary.intentional_count -ne $rows.Count) {
  throw "Approved-delta summary is not internally consistent and fully approved."
}
Write-Host "[ok] MIR approved delta binds the exact 2.4.5 and 2.4.9 archives, $($rows.Count) declared package paths, and no settings/migration/stream drift."
