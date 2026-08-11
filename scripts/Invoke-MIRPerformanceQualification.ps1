param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [Parameter(Mandatory)][string]$Candidate,
  [Parameter(Mandatory)][string]$PriorRelease,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ExpectedSourceCommit,
  [Parameter(Mandatory)][string]$ExpectedBaselineVersion,
  [Parameter(Mandatory)][string]$ExpectedFactorioVersion,
  [string]$CampaignPath = ".mir\performance-campaign.json",
  [string]$LocalModZipDir = "",
  [string]$OutputPath = "",
  [string]$ArtifactRoot = "",
  [string]$ArtifactCustodyRoot = "",
  [string[]]$ScratchRootCandidates = @(),
  [ValidateRange(1, 9999)][int]$AttemptOrdinal = 1,
  [ValidateRange(1, 10)][int]$WarmupRuns = 1,
  [ValidateRange(5, 25)][int]$MeasuredRuns = 5,
  [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "validation\ReleaseAttestations.ps1")
. (Join-Path $PSScriptRoot "validation\PerformanceCampaign.ps1")

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

$resolvedCampaignPath = if ([IO.Path]::IsPathRooted($CampaignPath)) { [IO.Path]::GetFullPath($CampaignPath) } else { [IO.Path]::GetFullPath((Join-Path $RepoRoot $CampaignPath)) }
$campaign = Get-Content -Raw -LiteralPath $resolvedCampaignPath | ConvertFrom-Json
$performanceArtifactsRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot "artifacts\performance"))
$usesGeneratedArtifactRoot = [string]::IsNullOrWhiteSpace($ArtifactRoot)
$generatedArtifactCustodyRoot = ""
if ($usesGeneratedArtifactRoot) {
  $candidateSha256 = Get-MIRPerformanceRawSha256 -Path $Candidate
  $baselineSha256 = Get-MIRPerformanceRawSha256 -Path $PriorRelease
  $factorioSha256 = Get-MIRPerformanceRawSha256 -Path $FactorioBin
  $planFingerprint = Get-MIRPerformanceTextSha256 -Value ("$candidateSha256`n$baselineSha256`n$factorioSha256`n$(Get-MIRPerformanceRawSha256 -Path $resolvedCampaignPath)`n$ExpectedSourceCommit")
  $targetCode = "f" + $factorioLine.Replace(".", "")
  $candidates = if ($ScratchRootCandidates.Count -gt 0) { $ScratchRootCandidates } else { @("C:\mir-tmp", "C:\tmp", [IO.Path]::GetTempPath()) }
  $staging = New-MIRPerformanceStagingRoot -Campaign $campaign -TargetCode $targetCode -TestId "performance.qualification" `
    -PlanFingerprint $planFingerprint -CandidateSha256 $candidateSha256 -BaselineSha256 $baselineSha256 -FactorioBinarySha256 $factorioSha256 `
    -DurableDestination ("artifacts/assurance/performance-custody/" + $planFingerprint.Substring(0, 16)) -AttemptOrdinal $AttemptOrdinal -ScratchRootCandidates $candidates
  $ArtifactRoot = [string]$staging.path
  $generatedArtifactCustodyRoot = if ([string]::IsNullOrWhiteSpace($ArtifactCustodyRoot)) {
    [IO.Path]::GetFullPath((Join-Path $RepoRoot ("artifacts\assurance\performance-custody\" + $planFingerprint.Substring(0, 16))))
  } elseif ([IO.Path]::IsPathRooted($ArtifactCustodyRoot)) {
    [IO.Path]::GetFullPath($ArtifactCustodyRoot)
  } else {
    [IO.Path]::GetFullPath((Join-Path $RepoRoot $ArtifactCustodyRoot))
  }
  $pathProjection = [pscustomobject]@{conservative_path_budget=$staging.conservative_path_budget;maximum_path_length=$staging.maximum_projected_path_length;maximum_path=$staging.maximum_projected_path}
} else {
  if (-not [IO.Path]::IsPathRooted($ArtifactRoot)) { $ArtifactRoot = Join-Path $RepoRoot $ArtifactRoot }
  $ArtifactRoot = [IO.Path]::GetFullPath($ArtifactRoot)
  $pathProjection = Get-MIRPerformancePathBudgetProjection -Campaign $campaign -ScratchRoot $ArtifactRoot
  if ([int]$pathProjection.maximum_path_length -gt [int]$pathProjection.conservative_path_budget) {
    throw "assurance-infrastructure-path-budget: performance staging exceeds the conservative Factorio path budget ($($pathProjection.maximum_path_length) > $($pathProjection.conservative_path_budget)) before Factorio launch: $($pathProjection.maximum_path)"
  }
  $safeArtifactPrefix = $performanceArtifactsRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  $provenanceMarker = Join-Path $ArtifactRoot "mir-staging-provenance.json"
  $controllerMarker = Join-Path $ArtifactRoot "control-plane-execution-root.json"
  if (-not $ArtifactRoot.StartsWith($safeArtifactPrefix, [StringComparison]::OrdinalIgnoreCase) -and
      -not (Test-Path -LiteralPath $provenanceMarker -PathType Leaf) -and
      -not (Test-Path -LiteralPath $controllerMarker -PathType Leaf)) {
    throw "Explicit performance artifact root must be beneath the governed performance root or bind compact staging provenance."
  }
}
Write-Host "[info] performance staging path budget: $($pathProjection.maximum_path_length)/$($pathProjection.conservative_path_budget)"
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
  CampaignPath = $CampaignPath
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
  -ExpectedFactorioVersion $ExpectedFactorioVersion `
  -CampaignPath $CampaignPath
if (-not $?) {
  throw "Fresh performance evidence validation failed."
}

if ($usesGeneratedArtifactRoot) {
  $relocation = Copy-MIRPerformanceArtifactsVerified -SourceRoot $ArtifactRoot -DestinationRoot $generatedArtifactCustodyRoot -ContentAddressedChild
  Write-Host "[ok] verified performance artifact relocation: $($relocation.destination_root) tree=$($relocation.artifact_tree_sha256)"
}

if (-not $KeepArtifacts -and (Test-Path -LiteralPath $ArtifactRoot -PathType Container)) {
  Remove-Item -LiteralPath $ArtifactRoot -Recurse -Force
  Write-Host "[cleanup] removed disposable performance artifacts: $ArtifactRoot"
}

Write-Host "[ok] fresh no-reuse performance qualification passed: $OutputPath"
