# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [string]$Path = "",
  [Parameter(Mandatory)][string]$Candidate,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ExpectedSourceCommit,
  [Parameter(Mandatory)][string]$ExpectedFactorioVersion
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"
$ErrorActionPreference = "Stop"
. (Join-Path $MirLegacyScriptRoot "validation\ReleaseAttestations.ps1")
$result = Test-MIRManualReleaseAttestation -RepoRoot $RepoRoot -Path $Path -Candidate $Candidate `
  -FactorioBin $FactorioBin -ExpectedSourceCommit $ExpectedSourceCommit `
  -ExpectedFactorioVersion $ExpectedFactorioVersion
Write-Host "[ok] MIR manual package review attestation passed: $($result.sha256)"
