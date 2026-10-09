[CmdletBinding()]
param(
  [ValidateSet('Reconcile','Criterion')][string]$Mode = 'Reconcile',
  [Parameter(Mandatory)][string]$RepoRoot,
  [Parameter(Mandatory)][string]$CandidateManifestPath,
  [hashtable]$PredecessorZips = @{},
  [hashtable]$UpgradeReceipts = @{},
  [string]$OutputRoot = '',
  [ValidateSet('fresh-exact-loads','settings-profile-continuity','research-progression','migrations-two-reload','compatibility-canaries','target-omissions','performance-telemetry','package-exclusion','deterministic-reconstruction')][string]$Criterion = '',
  [string[]]$ObservationPaths = @(),
  [string[]]$ObservedTargets = @(),
  [hashtable]$NotApplicableTargetReasons = @{},
  [string]$Claim = '',
  [string]$KnownLimitations = '',
  [string]$OutputPath = '',
  [string]$PublishedMaintenancePredecessorManifestPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1')
switch ($Mode) {
  'Reconcile' {
    if ($PredecessorZips.Count -eq 0 -or $UpgradeReceipts.Count -eq 0 -or [string]::IsNullOrWhiteSpace($OutputRoot)) {
      throw '[mir42-nine-reconciliation-inputs-required]'
    }
    Invoke-MIR42NineTargetEvidenceReconciliation -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath -PredecessorZips $PredecessorZips -UpgradeReceipts $UpgradeReceipts -OutputRoot $OutputRoot -PublishedMaintenancePredecessorManifestPath $PublishedMaintenancePredecessorManifestPath | ConvertTo-Json -Depth 100
  }
  'Criterion' {
    foreach ($value in @($Criterion,$Claim,$KnownLimitations,$OutputPath)) {
      if ([string]::IsNullOrWhiteSpace([string]$value)) { throw '[mir42-nine-criterion-inputs-required]' }
    }
    if ($ObservationPaths.Count -eq 0 -or $ObservedTargets.Count -eq 0) { throw '[mir42-nine-criterion-observations-required]' }
    New-MIR42NineTargetCriterionEvidence -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath -Criterion $Criterion `
      -ObservationPaths $ObservationPaths -ObservedTargets $ObservedTargets -NotApplicableTargetReasons $NotApplicableTargetReasons `
      -Claim $Claim -KnownLimitations $KnownLimitations -OutputPath $OutputPath `
      -PublishedMaintenancePredecessorManifestPath $PublishedMaintenancePredecessorManifestPath | ConvertTo-Json -Depth 100
  }
}
