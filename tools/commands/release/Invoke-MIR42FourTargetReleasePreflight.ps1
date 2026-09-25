param(
  [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$FinalSourceCommit,
  [Parameter(Mandatory)][string]$F210Zip,
  [Parameter(Mandatory)][string]$F200Zip,
  [Parameter(Mandatory)][string]$F110Zip,
  [Parameter(Mandatory)][string]$F100Zip,
  [Parameter(Mandatory)][string]$OutputRoot,
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')
$result = Invoke-MIR42FourTargetReleasePreflight @PSBoundParameters
$result | ConvertTo-Json -Depth 20
