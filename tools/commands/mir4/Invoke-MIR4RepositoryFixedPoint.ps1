# MIR4-REPOSITORY-COMPATIBILITY-COMMAND
param(
  [ValidateSet('generate','check','inventory','initialize')][string]$Command='check',
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputPath=''
)
& (Join-Path $RepoRoot 'tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1') -Command $Command -RepoRoot $RepoRoot -OutputPath $OutputPath
