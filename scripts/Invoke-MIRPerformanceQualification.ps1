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
  [ValidateRange(5, 25)][int]$MeasuredRuns = 5,
  [switch]$KeepArtifacts
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

$performanceArtifactsRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot "artifacts\performance"))
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
  $ArtifactRoot = Join-Path $performanceArtifactsRoot "$($candidateInfo.version)-qualification-$((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))"
} elseif (-not [IO.Path]::IsPathRooted($ArtifactRoot)) {
  $ArtifactRoot = Join-Path $RepoRoot $ArtifactRoot
}
$ArtifactRoot = [IO.Path]::GetFullPath($ArtifactRoot)
$safeArtifactPrefix = $performanceArtifactsRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $ArtifactRoot.StartsWith($safeArtifactPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Performance artifacts must stay inside $performanceArtifactsRoot."
}
$resolvedOutputPath = if ([IO.Path]::IsPathRooted($OutputPath)) { [IO.Path]::GetFullPath($OutputPath) } else { [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputPath)) }
if (-not $KeepArtifacts -and $resolvedOutputPath.StartsWith(($ArtifactRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
  throw "Compact performance evidence must remain outside the disposable artifact directory."
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
$measure.ArtifactRoot = $ArtifactRoot

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

if (-not $KeepArtifacts -and (Test-Path -LiteralPath $ArtifactRoot -PathType Container)) {
  Remove-Item -LiteralPath $ArtifactRoot -Recurse -Force
  Write-Host "[cleanup] removed disposable performance artifacts: $ArtifactRoot"
}

Write-Host "[ok] fresh no-reuse performance qualification passed: $OutputPath"
