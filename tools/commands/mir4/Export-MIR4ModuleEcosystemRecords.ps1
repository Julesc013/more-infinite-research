param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/m4c02-module-ecosystem',
  [string]$CandidateZip='build/mir4/m4c02-target-products/packages/more-infinite-research_4.0.21000.zip',
  [switch]$Check
)

& (Join-Path $PSScriptRoot '../../mir/cli/Export-MIR4ModuleEcosystemRecords.ps1') @PSBoundParameters
