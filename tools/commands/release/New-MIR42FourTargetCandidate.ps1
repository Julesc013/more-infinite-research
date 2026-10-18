[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RepoRoot,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$FinalSourceCommit,
  [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9.-]{0,47}$')][string]$BuildId,
  [ValidateSet('4.2.0','4.2.1','4.2.2','4.2.3','4.3.0','4.3.1','4.4.0','4.4.1','4.4.2','4.5.0','4.5.1','4.5.2','4.6.0')][string]$SourceVersion = '4.2.0',
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
