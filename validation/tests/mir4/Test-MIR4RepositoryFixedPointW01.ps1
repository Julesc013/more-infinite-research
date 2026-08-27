# MIR4-REPOSITORY-COMPATIBILITY-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
& (Join-Path $RepoRoot 'tests/repository/Test-MIR4RepositoryFixedPoint.ps1') -RepoRoot $RepoRoot
