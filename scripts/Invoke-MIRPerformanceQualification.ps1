param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [Parameter(Mandatory)][string]$Candidate,
  [Parameter(Mandatory)][string]$PriorRelease,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ExpectedSourceCommit,
  [Parameter(Mandatory)][string]$ExpectedBaselineVersion,
  [Parameter(Mandatory)][string]$ExpectedFactorioVersion,
  [string]$LocalModZipDir = "",
  [string]$OutputPath = "",
  [string]$ArtifactRoot = "",
  [ValidateRange(1, 10)][int]$WarmupRuns = 1,
  [ValidateRange(5, 25)][int]$MeasuredRuns = 5
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "validation\ReleaseAttestations.ps1")

$candidateInfo = Get-MIRReleasePackageInfo -Path $Candidate
$versionParts = @([string]$ExpectedFactorioVersion -split '\.')
if ($versionParts.Count -lt 2) { throw "ExpectedFactorioVersion must identify a target line." }
$factorioLine = $versionParts[0..1] -join "."
if ([string]::IsNullOrWhiteSpace($LocalModZipDir)) {
  $LocalModZipDir = Join-Path (Split-Path -Parent $RepoRoot) "testmods_$factorioLine"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = ".mir\evidence\$($candidateInfo.version)-performance-regression.json"
}

$measure = @{
  RepoRoot = $RepoRoot
  Candidate = $Candidate
  PriorRelease = $PriorRelease
  FactorioBin = $FactorioBin
  ExpectedSourceCommit = $ExpectedSourceCommit
  LocalModZipDir = $LocalModZipDir
  OutputPath = $OutputPath
  WarmupRuns = $WarmupRuns
  MeasuredRuns = $MeasuredRuns
}
if (-not [string]::IsNullOrWhiteSpace($ArtifactRoot)) {
  $measure.ArtifactRoot = $ArtifactRoot
}

& (Join-Path $PSScriptRoot "Measure-MIRPerformanceRegression.ps1") @measure
if (-not $?) {
  throw "Fresh performance evidence production failed."
}

& (Join-Path $PSScriptRoot "Test-MIRPerformanceRegression.ps1") `
  -RepoRoot $RepoRoot `
  -Path $OutputPath `
  -Candidate $Candidate `
  -PriorRelease $PriorRelease `
  -FactorioBin $FactorioBin `
  -ExpectedSourceCommit $ExpectedSourceCommit `
  -ExpectedBaselineVersion $ExpectedBaselineVersion `
  -ExpectedFactorioVersion $ExpectedFactorioVersion
if (-not $?) {
  throw "Fresh performance evidence validation failed."
}

Write-Host "[ok] fresh no-reuse performance qualification passed: $OutputPath"
