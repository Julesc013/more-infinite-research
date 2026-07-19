param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$Path = "",
  [Parameter(Mandatory)][string]$Candidate,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ExpectedSourceCommit,
  [Parameter(Mandatory)][string]$ExpectedFactorioVersion
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "validation\ReleaseAttestations.ps1")
$result = Test-MIRManualReleaseAttestation -RepoRoot $RepoRoot -Path $Path -Candidate $Candidate `
  -FactorioBin $FactorioBin -ExpectedSourceCommit $ExpectedSourceCommit `
  -ExpectedFactorioVersion $ExpectedFactorioVersion
Write-Host "[ok] MIR manual package review attestation passed: $($result.sha256)"
