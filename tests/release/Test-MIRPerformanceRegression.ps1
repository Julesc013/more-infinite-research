# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [string]$Path = "",
  [Parameter(Mandatory)][string]$Candidate,
  [Parameter(Mandatory)][string]$PriorRelease,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ExpectedSourceCommit,
  [Parameter(Mandatory)][string]$ExpectedBaselineVersion,
  [Parameter(Mandatory)][string]$ExpectedFactorioVersion,
  [string]$CampaignPath = ""
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"
$ErrorActionPreference = "Stop"
. (Join-Path $MirLegacyScriptRoot "validation\ReleaseAttestations.ps1")
$result = Test-MIRRuntimePerformanceEvidence -RepoRoot $RepoRoot -Path $Path -Candidate $Candidate `
  -PriorRelease $PriorRelease -FactorioBin $FactorioBin -ExpectedSourceCommit $ExpectedSourceCommit `
  -ExpectedBaselineVersion $ExpectedBaselineVersion `
  -ExpectedFactorioVersion $ExpectedFactorioVersion `
  -CampaignPath $CampaignPath
Write-Host "[ok] MIR runtime performance regression evidence passed: $($result.sha256)"
