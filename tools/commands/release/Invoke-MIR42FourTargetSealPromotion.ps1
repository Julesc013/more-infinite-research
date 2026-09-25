[CmdletBinding()]
param(
  [ValidateSet('Readiness','Seal','PromotionPlan')][string]$Mode = 'Readiness',
  [Parameter(Mandatory)][string]$CandidateManifestPath,
  [string]$QualificationPath = '',
  [string]$IndependentVerificationPath = '',
  [string]$SigningCeremonyPath = '',
  [string]$SourceFreezeAuthorityPath = '',
  [string]$TechnicalSealPath = '',
  [string]$OutputPath = '',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42ProtectedMainPromotion.ps1')

switch ($Mode) {
  'Readiness' {
    $result = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
      -QualificationPath $QualificationPath -IndependentVerificationPath $IndependentVerificationPath `
      -SigningCeremonyPath $SigningCeremonyPath -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath
    $result.PSObject.Properties.Remove('_state')
    $result | ConvertTo-Json -Depth 30
  }
  'Seal' {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw '[mir42-seal-output-path-required]' }
    New-MIR42FourTargetTechnicalSeal -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
      -QualificationPath $QualificationPath -IndependentVerificationPath $IndependentVerificationPath `
      -SigningCeremonyPath $SigningCeremonyPath -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -OutputPath $OutputPath | ConvertTo-Json -Depth 30
  }
  'PromotionPlan' {
    if ([string]::IsNullOrWhiteSpace($TechnicalSealPath)) { throw '[mir42-promotion-technical-seal-required]' }
    Get-MIR42ProtectedMainPromotionPlan -RepoRoot $RepoRoot -TechnicalSealPath $TechnicalSealPath -CandidateManifestPath $CandidateManifestPath | ConvertTo-Json -Depth 30
  }
}
