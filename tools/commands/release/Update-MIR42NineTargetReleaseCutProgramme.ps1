[CmdletBinding()]
param(
  [ValidateSet('Prepare','AdvanceWrittenGo')][string]$Mode = 'Prepare',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputPath = '.mir/releases/governance/mir4/MIR42-Nine-Target-Release-Cut-ProgrammeV1.json',
  [string]$MaintainerAuthorizationPath = '',
  [string]$CandidateManifestPath = '',
  [string]$CheckpointRoot = 'build/release-programme-checkpoints'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $RepoRoot $OutputPath }
if ($Mode -ceq 'Prepare') {
  New-MIR42NineTargetReleaseCutProgramme -RepoRoot $RepoRoot -OutputPath $OutputPath | ConvertTo-Json -Depth 30
  return
}
if ([string]::IsNullOrWhiteSpace($MaintainerAuthorizationPath) -or [string]::IsNullOrWhiteSpace($CandidateManifestPath)) {
  throw '[mir42-nine-programme-advance-inputs-required]'
}
if (-not [IO.Path]::IsPathRooted($CheckpointRoot)) { $CheckpointRoot = Join-Path $RepoRoot $CheckpointRoot }
Advance-MIR42NineTargetReleaseCutProgramme -RepoRoot $RepoRoot -OutputPath $OutputPath -MaintainerAuthorizationPath $MaintainerAuthorizationPath `
  -CandidateManifestPath $CandidateManifestPath -CheckpointRoot $CheckpointRoot | ConvertTo-Json -Depth 30
