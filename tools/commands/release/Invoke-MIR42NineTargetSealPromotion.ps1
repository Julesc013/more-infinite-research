[CmdletBinding()]
param(
  [ValidateSet('Readiness','EngineEvidence','Seal','PromotionPlan','MainReadback')][string]$Mode = 'Readiness',
  [Parameter(Mandatory)][string]$CandidateManifestPath,
  [string]$QualificationPath = '',
  [string]$RealEngineCampaignPath = '',
  [string]$IndependentVerificationPath = '',
  [string]$SigningCeremonyPath = '',
  [string]$T16TrustRootPath = '',
  [string]$OperatorTrustSourcePath = '',
  [string]$T16ProtectedRootPath = '',
  [string]$T16ImmutableAnchorPath = '',
  [string]$T16ApprovedOwnerSid = '',
  [string[]]$T16ApprovedMutationSids = @(),
  [string]$SourceFreezeAuthorityPath = '',
  [string]$ReviewerAttestationPath = '',
  [string]$SshKeygenPath = '',
  [string]$EngineRunPath = '',
  [string]$TechnicalSealPath = '',
  [string]$OfflineRestoreDrillPath = '',
  [string]$PrimaryRepoRoot = '',
  [int]$PullRequestNumber = 0,
  [string]$IntentionPath = '',
  [string]$PromotionRequestPath = '',
  [string]$OutputPath = '',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42ProtectedMainPromotion.ps1')

switch ($Mode) {
  'Readiness' {
    $result = Get-MIR42NineTargetTechnicalSealReadiness -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
      -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
      -SigningCeremonyPath $SigningCeremonyPath -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath -T16ProtectedRootPath $T16ProtectedRootPath -T16ImmutableAnchorPath $T16ImmutableAnchorPath -T16ApprovedOwnerSid $T16ApprovedOwnerSid -T16ApprovedMutationSids $T16ApprovedMutationSids `
      -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath
    $result.PSObject.Properties.Remove('_state')
    $result | ConvertTo-Json -Depth 30
  }
  'EngineEvidence' {
    if ([string]::IsNullOrWhiteSpace($QualificationPath)) { throw '[mir42-engine-evidence-reconciliation-required]' }
    if ([string]::IsNullOrWhiteSpace($EngineRunPath)) { throw '[mir42-engine-evidence-run-required]' }
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw '[mir42-engine-evidence-output-required]' }
    New-MIR42NineTargetRealEngineEvidenceBinder -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
      -EvidenceReconciliationPath $QualificationPath -EngineRunPath $EngineRunPath -OutputPath $OutputPath | ConvertTo-Json -Depth 30
  }
  'Seal' {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw '[mir42-seal-output-path-required]' }
    New-MIR42NineTargetTechnicalSeal -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
      -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
      -SigningCeremonyPath $SigningCeremonyPath -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath -T16ProtectedRootPath $T16ProtectedRootPath -T16ImmutableAnchorPath $T16ImmutableAnchorPath -T16ApprovedOwnerSid $T16ApprovedOwnerSid -T16ApprovedMutationSids $T16ApprovedMutationSids `
      -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath -OutputPath $OutputPath | ConvertTo-Json -Depth 30
  }
  'PromotionPlan' {
    if ([string]::IsNullOrWhiteSpace($TechnicalSealPath)) { throw '[mir42-promotion-technical-seal-required]' }
    if ([string]::IsNullOrWhiteSpace($OfflineRestoreDrillPath)) { throw '[mir42-promotion-offline-restore-drill-required]' }
    Get-MIR42NineTargetProtectedMainPromotionPlan -RepoRoot $RepoRoot -TechnicalSealPath $TechnicalSealPath -CandidateManifestPath $CandidateManifestPath `
      -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
      -SigningCeremonyPath $SigningCeremonyPath -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath -T16ProtectedRootPath $T16ProtectedRootPath -T16ImmutableAnchorPath $T16ImmutableAnchorPath -T16ApprovedOwnerSid $T16ApprovedOwnerSid -T16ApprovedMutationSids $T16ApprovedMutationSids `
      -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath -OfflineRestoreDrillPath $OfflineRestoreDrillPath | ConvertTo-Json -Depth 30
  }
  'MainReadback' {
    if ([string]::IsNullOrWhiteSpace($PrimaryRepoRoot)) { throw '[mir42-main-readback-primary-required]' }
    if ($PullRequestNumber -le 0) { throw '[mir42-main-readback-pull-request-required]' }
    if ([string]::IsNullOrWhiteSpace($IntentionPath) -or [string]::IsNullOrWhiteSpace($PromotionRequestPath)) { throw '[mir42-main-readback-persisted-request-required]' }
    if ([string]::IsNullOrWhiteSpace($TechnicalSealPath)) { throw '[mir42-main-readback-technical-seal-required]' }
    if ([string]::IsNullOrWhiteSpace($OfflineRestoreDrillPath)) { throw '[mir42-main-readback-offline-restore-drill-required]' }
    $result = Get-MIR42NineTargetProtectedMainReadback -RepoRoot $RepoRoot -PrimaryRepoRoot $PrimaryRepoRoot -PullRequestNumber $PullRequestNumber -IntentionPath $IntentionPath -PromotionRequestPath $PromotionRequestPath -TechnicalSealPath $TechnicalSealPath -CandidateManifestPath $CandidateManifestPath `
      -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
      -SigningCeremonyPath $SigningCeremonyPath -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath -T16ProtectedRootPath $T16ProtectedRootPath -T16ImmutableAnchorPath $T16ImmutableAnchorPath -T16ApprovedOwnerSid $T16ApprovedOwnerSid -T16ApprovedMutationSids $T16ApprovedMutationSids `
      -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath -OfflineRestoreDrillPath $OfflineRestoreDrillPath
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
      Write-MIR42NineTargetProtectedMainReadback -Record $result -PrimaryRepoRoot $PrimaryRepoRoot -OutputPath $OutputPath | Out-Null
    }
    $result | ConvertTo-Json -Depth 100
  }
}
