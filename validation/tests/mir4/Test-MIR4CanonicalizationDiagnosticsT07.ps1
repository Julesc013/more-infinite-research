# MIR4-CANONICALIZATION-COMPATIBILITY-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
& (Join-Path $RepoRoot 'tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1') -RepoRoot $RepoRoot
