param(
  [Parameter(Mandatory)][string]$ContextPath,
  [Parameter(Mandatory)][string]$SourceRepoRoot,
  [Parameter(Mandatory)][ValidateSet("identity", "composition", "determinism")][string]$Check,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$sourceRepo = (Resolve-Path -LiteralPath $SourceRepoRoot).Path
$context = (Resolve-Path -LiteralPath $ContextPath).Path
. (Join-Path $repo "scripts/validation/PackageIdentity.ps1")
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}

[void](Assert-MIRCPVerificationContext -Path $context)
$descriptor = Get-Content -Raw -LiteralPath (Join-Path $context "candidate-descriptor.json") | ConvertFrom-Json
$controlLock = Get-Content -Raw -LiteralPath (Join-Path $context "control-plane-lock.json") | ConvertFrom-Json
$candidate = Join-Path $context "candidate.zip"
$sourceCommit = Get-MIRGitCommit -RepoRoot $sourceRepo
if ($sourceCommit -ne [string]$controlLock.scenario_source_commit) {
  throw "Qualification source checkout $sourceCommit does not match the immutable context source lock."
}
$sourceTree = ([string](& git -C $sourceRepo rev-parse "HEAD^{tree}")).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceTree -ne [string]$controlLock.scenario_source_tree) {
  throw "Qualification source tree does not match the immutable context source lock."
}
$sourceWorktreeSha256 = Get-MIRCPTrackedWorktreeSha256 -SourceRepoRoot $sourceRepo
if ($sourceWorktreeSha256 -ne [string]$controlLock.scenario_source_worktree_sha256) {
  throw "Qualification source tracked state does not match the immutable context source lock."
}
if (Test-MIRPackageSourceGitDirty -RepoRoot $sourceRepo) {
  throw "Package source checkout has package-visible changes."
}
$sourceContent = Get-MIRPackageSourceFingerprint -RepoRoot $sourceRepo
$archiveSha = Get-MIRFileSha256 -Path $candidate
$archiveContent = Get-MIRZipContentFingerprint -Path $candidate
if ($sourceContent -ne [string]$descriptor.source_sha256 -or $sourceContent -ne [string]$descriptor.content_sha256) {
  throw "Package source content does not match the immutable context descriptor."
}
if ($archiveSha -ne [string]$descriptor.archive_sha256 -or $archiveContent -ne [string]$descriptor.content_sha256) {
  throw "Context candidate archive identity does not match its source or descriptor."
}
if ((Get-Item -LiteralPath $candidate).Length -ne [int64]$descriptor.bytes) {
  throw "Context candidate byte count does not match release authority."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($candidate)
try {
  $archiveEntries = @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | ForEach-Object {
    $slash = $_.FullName.IndexOf("/")
    if ($slash -lt 1) { throw "Candidate entry has no single package root: $($_.FullName)" }
    [pscustomobject][ordered]@{root=$_.FullName.Substring(0, $slash); relative=$_.FullName.Substring($slash + 1)}
  })
} finally {
  $zip.Dispose()
}
$roots = @($archiveEntries.root | Sort-Object -Unique)
$expectedEntries = @(Get-MIRPackageSourceFiles -RepoRoot $sourceRepo)
$actualEntries = @($archiveEntries.relative | Sort-Object)
if ($roots.Count -ne 1) { throw "Candidate archive must contain exactly one package root." }
if ($archiveEntries.Count -ne [int]$descriptor.entries -or $archiveEntries.Count -ne $expectedEntries.Count) {
  throw "Candidate archive entry count does not match source and release authority."
}
if (($actualEntries -join "`n") -ne (($expectedEntries | Sort-Object) -join "`n")) {
  throw "Candidate archive composition does not exactly match governed package-source roots."
}

$rebuilds = @()
if ($Check -eq "determinism") {
  $info = Get-Content -Raw -LiteralPath (Join-Path $sourceRepo "info.json") | ConvertFrom-Json
  $archiveName = "$($info.name)_$($info.version).zip"
  foreach ($relativeOutput in @("build/control-plane-v5-package-a", "build/control-plane-v5-package-b")) {
    & (Join-Path $sourceRepo "scripts/Build-MIRPackage.ps1") -OutputDir $relativeOutput -CompressionLevel Optimal | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Exact-source deterministic package build failed." }
    $rebuilt = Join-Path $sourceRepo "$relativeOutput/$archiveName"
    $rebuilds += [pscustomobject][ordered]@{path=$relativeOutput;sha256=(Get-MIRFileSha256 -Path $rebuilt);content_sha256=(Get-MIRZipContentFingerprint -Path $rebuilt)}
  }
  foreach ($rebuilt in $rebuilds) {
    if ([string]$rebuilt.sha256 -ne [string]$descriptor.archive_sha256 -or [string]$rebuilt.content_sha256 -ne [string]$descriptor.content_sha256) {
      throw "Exact-source rebuild is not byte- and content-identical to the context candidate."
    }
  }
}

[pscustomobject][ordered]@{
  status = "passed"
  check = $Check
  qualification_source_role = [string]$controlLock.scenario_source_role
  source_commit = $sourceCommit
  source_tree = $sourceTree
  source_worktree_sha256 = $sourceWorktreeSha256
  archive_sha256 = $archiveSha
  content_sha256 = $archiveContent
  bytes = (Get-Item -LiteralPath $candidate).Length
  entries = $archiveEntries.Count
  rebuilds = @($rebuilds)
} | ConvertTo-Json -Depth 8
