param(
  [Parameter(Mandatory)]
  [ValidateSet("0.12", "0.11", "0.10", "0.9", "0.8", "0.7", "0.6")]
  [string]$FactorioVersion,
  [string]$QualificationSummaryPath = "",
  [string]$PackagePath = "",
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
Import-Module (Join-Path $PSScriptRoot "Museum\MuseumCompiler.psm1") -Force
$catalog = Get-MIRMuseumCatalog -Path (Join-Path $repo ".mir\museum-targets.json")
$target = Get-MIRMuseumTarget -Catalog $catalog -FactorioVersion $FactorioVersion
if ([string]::IsNullOrWhiteSpace($QualificationSummaryPath)) { $QualificationSummaryPath = Join-Path $repo ".mir\evidence\$($target.version)-qualification-summary.json" }
if ([string]::IsNullOrWhiteSpace($PackagePath)) { $PackagePath = Join-Path $repo "dist\$($catalog.mod_name)_$($target.version).zip" }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $repo ".mir\evidence\$($target.version)-candidate-seal.json" }
foreach ($name in @("QualificationSummaryPath", "PackagePath", "OutputPath")) {
  $value = Get-Variable -Name $name -ValueOnly
  if (-not [IO.Path]::IsPathRooted($value)) { Set-Variable -Name $name -Value (Join-Path $repo $value) }
}
if (@(& git -C $repo status --short).Count -ne 0) { throw "Commit qualification evidence and package before creating a seal." }
$summary = Get-Content -Raw -LiteralPath $QualificationSummaryPath | ConvertFrom-Json
if ([string]$summary.status -ne "passed" -or [string]$summary.factorio -ne $FactorioVersion) { throw "Qualification summary is not passed for $FactorioVersion." }
$identity = Get-MIRMuseumZipIdentity -Path $PackagePath
$sourceLockPath = Join-Path $repo ".mir\backport-source-lock.json"
if (-not (Test-Path -LiteralPath $sourceLockPath -PathType Leaf)) { throw "Museum sealing requires a validated backport source lock." }
$sourceLock = Get-Content -Raw -LiteralPath $sourceLockPath | ConvertFrom-Json
if ([string]$sourceLock.target -ne $FactorioVersion -or [string]$sourceLock.mir_version -ne [string]$target.version) { throw "Museum source-lock identity mismatch." }

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

$profileText = ($target | ConvertTo-Json -Depth 30 -Compress)
$harnessPaths = @(
  ".mir\canonical-lower-features.json",
  ".mir\museum-targets.json",
  "scripts\Museum\MuseumCompiler.psm1",
  "scripts\Build-MIRMuseumTarget.ps1",
  "scripts\Test-MIRMuseumCompiler.ps1",
  "scripts\Test-MIRMuseumRuntime.ps1",
  "scripts\New-MIRMuseumQualification.ps1",
  "scripts\New-MIRMuseumSeal.ps1",
  "scripts\Test-MIRMuseumSeal.ps1"
)
$sourcePaths = @("info.json", "config.lua", "data.lua", "locale\en\more-infinite-research.cfg", ".mir\museum\stream-manifest.json", ".mir\museum\balance.json")
$record = [ordered]@{
  schema = 1
  kind = "mir-qualified-candidate-seal"
  branch = [string]$target.branch
  release = [string]$target.version
  target_factorio = $FactorioVersion
  mir_version = [string]$target.version
  target = $FactorioVersion
  canonical_dev_anchor = [string]$sourceLock.canonical_dev_anchor
  backport_source_lock_sha256 = Get-RepositoryTextSha256 $sourceLockPath
  canonical_feature_model_sha256 = Get-RepositoryTextSha256 (Join-Path $repo ".mir\canonical-lower-features.json")
  source_commit = (& git -C $repo rev-parse HEAD).Trim()
  candidate = [ordered]@{
    path = (Resolve-Path -LiteralPath $PackagePath).Path.Substring($repo.Path.Length + 1).Replace('\', '/')
    sha256 = $identity.sha256
    size_bytes = $identity.size
    entries = $identity.entries
    content_fingerprint = $identity.package_content_sha256
    package_source_fingerprint = Get-FileSetFingerprint $sourcePaths
  }
  target_profile_sha256 = Get-StringSha256 ($profileText + "`n")
  validation_harness_fingerprint = Get-FileSetFingerprint $harnessPaths
  factorio_binary_sha256 = Get-MIRSha256 ([string]$target.binary).Replace('/', '\')
  qualification_summary_sha256 = Get-RepositoryTextSha256 $QualificationSummaryPath
  release_actions = "not-run-maintainer-only"
}
Set-MIRUtf8Text -Path $OutputPath -Text (($record | ConvertTo-Json -Depth 20) + "`n")
$record | ConvertTo-Json -Depth 20
