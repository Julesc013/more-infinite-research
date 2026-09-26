[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RepoRoot,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$FinalSourceCommit,
  [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9.-]{0,47}$')][string]$BuildId,
  [string[]]$SelectedTargets,
  [string]$OutputRoot,
  [ValidateRange(1, 9223372036854775807)][Int64]$MinimumFreeMemoryBytes = 1GB,
  [ValidateRange(1, 9223372036854775807)][Int64]$MinimumFreeWorkBytes = 2GB
)

Set-StrictMode -Version Latest

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42CandidateBuild.ps1')

$result = New-MIR42FourTargetCandidate @PSBoundParameters
$result | ConvertTo-Json -Depth 100
if (-not [bool]$result.build_complete) {
  exit 1
}
