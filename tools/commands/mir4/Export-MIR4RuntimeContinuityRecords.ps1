# MIR4-RUNTIME-CONTINUITY-COMPATIBILITY-COMMAND
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/m4c02-runtime-continuity',
  [string]$CandidateZip='build/mir4/m4c02-target-products/packages/more-infinite-research_4.0.21000.zip',
  [switch]$Check
)
& (Join-Path $RepoRoot 'tools/mir/cli/Export-MIR4RuntimeContinuityRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $OutputRoot -CandidateZip $CandidateZip -Check:$Check
