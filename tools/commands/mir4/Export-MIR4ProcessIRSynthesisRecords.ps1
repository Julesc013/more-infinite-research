param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/m4c02-processir-synthesis',
  [switch]$Check
)
& (Join-Path (Resolve-Path -LiteralPath $RepoRoot).Path 'tools/mir/cli/Export-MIR4ProcessIRSynthesisRecords.ps1') @PSBoundParameters
