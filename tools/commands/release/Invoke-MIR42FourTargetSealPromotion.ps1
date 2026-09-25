[CmdletBinding()]
param(
  [ValidateSet('Readiness','EngineEvidence','Seal','PromotionPlan')][string]$Mode = 'Readiness',
  [Parameter(Mandatory)][string]$CandidateManifestPath,
  [string]$QualificationPath = '',
  [string]$RealEngineCampaignPath = '',
  [string]$IndependentVerificationPath = '',
  [string]$SigningCeremonyPath = '',
  [string]$T16TrustRootPath = '',
  [string]$OperatorTrustSourcePath = '',
  [string]$SourceFreezeAuthorityPath = '',
  [string]$ReviewerAttestationPath = '',
  [string]$SshKeygenPath = '',
  [string]$EngineRunPath = '',
  [string]$TechnicalSealPath = '',
  [string]$OfflineRestoreDrillPath = '',
  [string]$OutputPath = '',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42ProtectedMainPromotion.ps1')

switch ($Mode) {
  'Readiness' {
    $result = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
      -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
      -SigningCeremonyPath $SigningCeremonyPath -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath `
      -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath
    $result.PSObject.Properties.Remove('_state')
    $result | ConvertTo-Json -Depth 30
  }
  'EngineEvidence' {
    if ([string]::IsNullOrWhiteSpace($QualificationPath)) { throw '[mir42-engine-evidence-reconciliation-required]' }
    if ([string]::IsNullOrWhiteSpace($EngineRunPath)) { throw '[mir42-engine-evidence-run-required]' }
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw '[mir42-engine-evidence-output-required]' }
    New-MIR42FourTargetRealEngineEvidenceBinder -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
      -EvidenceReconciliationPath $QualificationPath -EngineRunPath $EngineRunPath -OutputPath $OutputPath | ConvertTo-Json -Depth 30
  }
  'Seal' {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw '[mir42-seal-output-path-required]' }
    New-MIR42FourTargetTechnicalSeal -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
      -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
      -SigningCeremonyPath $SigningCeremonyPath -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath `
      -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath -OutputPath $OutputPath | ConvertTo-Json -Depth 30
  }
  'PromotionPlan' {
    if ([string]::IsNullOrWhiteSpace($TechnicalSealPath)) { throw '[mir42-promotion-technical-seal-required]' }
    if ([string]::IsNullOrWhiteSpace($OfflineRestoreDrillPath)) { throw '[mir42-promotion-offline-restore-drill-required]' }
    Get-MIR42ProtectedMainPromotionPlan -RepoRoot $RepoRoot -TechnicalSealPath $TechnicalSealPath -CandidateManifestPath $CandidateManifestPath `
      -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
      -SigningCeremonyPath $SigningCeremonyPath -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath `
      -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath -OfflineRestoreDrillPath $OfflineRestoreDrillPath | ConvertTo-Json -Depth 30
  }
}
