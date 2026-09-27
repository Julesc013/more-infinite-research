[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RepoRoot,
  [Parameter(Mandatory)][string]$CandidateManifestPath,
  [Parameter(Mandatory)][string]$QualificationPath,
  [Parameter(Mandatory)][hashtable]$PredecessorZips,
  [Parameter(Mandatory)][hashtable]$UpgradeReceipts,
  [Parameter(Mandatory)][string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42IndependentEvidenceRehash.ps1')
Invoke-MIR42NineTargetIndependentEvidenceRehash @PSBoundParameters | ConvertTo-Json -Depth 100
