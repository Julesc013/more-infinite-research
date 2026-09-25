[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RepoRoot,
  [Parameter(Mandatory)][string]$CandidateManifestPath,
  [Parameter(Mandatory)][string]$F210PredecessorZip,
  [Parameter(Mandatory)][string]$F200PredecessorZip,
  [Parameter(Mandatory)][string]$F110PredecessorZip,
  [Parameter(Mandatory)][string]$F100PredecessorZip,
  [Parameter(Mandatory)][string]$F210UpgradeReceipt,
  [Parameter(Mandatory)][string]$F200UpgradeReceipt,
  [Parameter(Mandatory)][string]$F110UpgradeReceipt,
  [Parameter(Mandatory)][string]$F100UpgradeReceipt,
  [Parameter(Mandatory)][string]$OutputRoot
)

Set-StrictMode -Version Latest

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42ExactCandidateQualification.ps1')

Invoke-MIR42FourTargetExactCandidateQualification @PSBoundParameters | ConvertTo-Json -Depth 100
