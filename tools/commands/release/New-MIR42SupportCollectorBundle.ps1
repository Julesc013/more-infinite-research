[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourceCommit,
  [Parameter(Mandatory)][string]$OutputPath,
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42SupportCollectorBundle.ps1')
New-MIR42SupportCollectorBundle -RepoRoot $RepoRoot -SourceCommit $SourceCommit -OutputPath $OutputPath | ConvertTo-Json -Depth 10
