# MIR4-SEMANTIC-COMPILER-COMPATIBILITY-COMMAND
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/m4c02-semantic-compiler',
  [switch]$Check
)
& (Join-Path $RepoRoot 'tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $OutputRoot -Check:$Check
