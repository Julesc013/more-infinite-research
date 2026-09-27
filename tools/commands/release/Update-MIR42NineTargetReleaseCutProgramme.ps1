[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputPath = '.mir/releases/governance/mir4/MIR42-Nine-Target-Release-Cut-ProgrammeV1.json'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $RepoRoot $OutputPath }
New-MIR42NineTargetReleaseCutProgramme -RepoRoot $RepoRoot -OutputPath $OutputPath | ConvertTo-Json -Depth 30
