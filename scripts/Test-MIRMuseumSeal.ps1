param(
  [Parameter(Mandatory)]
  [ValidateSet("0.12", "0.11", "0.10", "0.9", "0.8", "0.7", "0.6")]
  [string]$FactorioVersion,
  [string]$SealPath = ""
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
Import-Module (Join-Path $PSScriptRoot "Museum\MuseumCompiler.psm1") -Force
$catalog = Get-MIRMuseumCatalog -Path (Join-Path $repo ".mir\museum-targets.json")
$target = Get-MIRMuseumTarget -Catalog $catalog -FactorioVersion $FactorioVersion
if ([string]::IsNullOrWhiteSpace($SealPath)) { $SealPath = Join-Path $repo ".mir\evidence\$($target.version)-candidate-seal.json" }
if (-not [IO.Path]::IsPathRooted($SealPath)) { $SealPath = Join-Path $repo $SealPath }
if (@(& git -C $repo status --short).Count -ne 0) { throw "Candidate worktree is not clean." }
$seal = Get-Content -Raw -LiteralPath $SealPath | ConvertFrom-Json
if ([int]$seal.schema -ne 1 -or [string]$seal.kind -ne "mir-qualified-candidate-seal") { throw "Invalid seal schema or kind." }
if ([string]$seal.branch -ne [string]$target.branch -or [string]$seal.release -ne [string]$target.version -or [string]$seal.target_factorio -ne $FactorioVersion) { throw "Seal target identity mismatch." }
$sourceLockPath = Join-Path $repo ".mir\backport-source-lock.json"
$sourceLock = Get-Content -Raw -LiteralPath $sourceLockPath | ConvertFrom-Json

function Get-StringSha256([string]$Text) {
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($Text)))
}
function Get-RepositoryTextSha256([string]$Path) {
  $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
  return Get-StringSha256 $text
}
function Get-FileSetFingerprint([string[]]$RelativePaths) {
  $lines = @($RelativePaths | Sort-Object | ForEach-Object { "$($_.Replace('\', '/'))|$(Get-RepositoryTextSha256 (Join-Path $repo $_))" })
  return Get-StringSha256 (($lines -join "`n") + "`n")
}

if ([string]$seal.mir_version -ne [string]$target.version -or [string]$seal.target -ne $FactorioVersion -or
    [string]$seal.canonical_dev_anchor -ne [string]$sourceLock.canonical_dev_anchor -or
    [string]$seal.backport_source_lock_sha256 -ne (Get-RepositoryTextSha256 $sourceLockPath) -or
    [string]$seal.canonical_feature_model_sha256 -ne (Get-RepositoryTextSha256 (Join-Path $repo ".mir\canonical-lower-features.json"))) {
  throw "Seal canonical source identity mismatch."
}
$profileText = ($target | ConvertTo-Json -Depth 30 -Compress)
$harnessPaths = @(
  ".mir\canonical-lower-features.json", ".mir\museum-targets.json", "scripts\Museum\MuseumCompiler.psm1",
  "scripts\Build-MIRMuseumTarget.ps1", "scripts\Test-MIRMuseumCompiler.ps1", "scripts\Test-MIRMuseumRuntime.ps1",
  "scripts\New-MIRMuseumQualification.ps1", "scripts\New-MIRMuseumSeal.ps1", "scripts\Test-MIRMuseumSeal.ps1"
)
$sourcePaths = @("info.json", "config.lua", "data.lua", "locale\en\more-infinite-research.cfg", ".mir\museum\stream-manifest.json", ".mir\museum\balance.json")
if ([string]$seal.target_profile_sha256 -ne (Get-StringSha256 ($profileText + "`n")) -or
    [string]$seal.validation_harness_fingerprint -ne (Get-FileSetFingerprint $harnessPaths) -or
    [string]$seal.candidate.package_source_fingerprint -ne (Get-FileSetFingerprint $sourcePaths)) {
  throw "Seal target profile, harness, or source fingerprint mismatch."
}
& git -C $repo merge-base --is-ancestor ([string]$seal.source_commit) HEAD
if ($LASTEXITCODE -ne 0) { throw "Sealed source commit is not an ancestor of HEAD." }
$packagePath = Join-Path $repo ([string]$seal.candidate.path).Replace('/', '\')
$identity = Get-MIRMuseumZipIdentity -Path $packagePath
if ($identity.sha256 -ne [string]$seal.candidate.sha256 -or $identity.size -ne [long]$seal.candidate.size_bytes -or $identity.entries -ne [int]$seal.candidate.entries -or $identity.package_content_sha256 -ne [string]$seal.candidate.content_fingerprint) { throw "Candidate package identity does not match seal." }
$blob = (& git -C $repo rev-parse "$($seal.source_commit):$($seal.candidate.path)" 2>$null).Trim()
$currentBlob = (& git -C $repo hash-object $packagePath).Trim()
if ([string]::IsNullOrWhiteSpace($blob) -or $blob -ne $currentBlob) { throw "Sealed source commit does not contain the exact candidate ZIP." }
$summaryPath = Join-Path $repo ".mir\evidence\$($target.version)-qualification-summary.json"
if ((Get-RepositoryTextSha256 $summaryPath) -ne [string]$seal.qualification_summary_sha256) { throw "Qualification summary hash mismatch." }
if ((Get-MIRSha256 ([string]$target.binary).Replace('/', '\')) -ne [string]$seal.factorio_binary_sha256) { throw "Factorio binary hash mismatch." }
[pscustomobject][ordered]@{
  schema = 1
  status = "passed"
  target = $FactorioVersion
  release = [string]$target.version
  source_commit = [string]$seal.source_commit
  candidate_sha256 = $identity.sha256
  seal_sha256 = Get-MIRSha256 $SealPath
} | ConvertTo-Json -Depth 10
