param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$Path = "",
  [Parameter(Mandatory)][string]$Candidate,
  [Parameter(Mandatory)][string]$PriorRelease,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ExpectedSourceCommit,
  [Parameter(Mandatory)][string]$ExpectedBaselineVersion,
  [Parameter(Mandatory)][string]$ExpectedFactorioVersion
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "validation\ReleaseAttestations.ps1")
$result = Test-MIRRuntimePerformanceEvidence -RepoRoot $RepoRoot -Path $Path -Candidate $Candidate `
  -PriorRelease $PriorRelease -FactorioBin $FactorioBin -ExpectedSourceCommit $ExpectedSourceCommit `
  -ExpectedBaselineVersion $ExpectedBaselineVersion `
  -ExpectedFactorioVersion $ExpectedFactorioVersion
Write-Host "[ok] MIR runtime performance regression evidence passed: $($result.sha256)"
