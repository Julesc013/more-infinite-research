[CmdletBinding()]
param(
  [ValidateSet('Inventory','VerifyBytes','PublicReadback','AuthorizePublication')][string]$Mode = 'Inventory',
  [string]$CandidateManifestPath = '',
  [string]$TechnicalSealPath = '',
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
  [string]$OfflineRestoreDrillPath = '',
  [string]$SourceVersion = '4.2.0',
  [string]$ReleaseTag = 'v4.2.0',
  [string]$AssetRoot = '',
  [string]$OutputPath = '',
  [string]$FrozenInventoryPath = '',
  [string]$DownloadedAssetRoot = '',
  [string]$PrimaryRepoRoot = '',
  [string]$MaintainerAuthorizationPath = '',
  [string]$MainReadbackPath = '',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42ReleaseAssets.ps1')
switch ($Mode) {
  'Inventory' {
    foreach ($path in @($CandidateManifestPath,$TechnicalSealPath,$QualificationPath,$RealEngineCampaignPath,$IndependentVerificationPath,$SigningCeremonyPath,$SourceFreezeAuthorityPath,$ReviewerAttestationPath,$SshKeygenPath,$OfflineRestoreDrillPath,$AssetRoot,$OutputPath)) {
      if ([string]::IsNullOrWhiteSpace($path)) { throw '[mir42-nine-release-assets-verified-inputs-required]' }
    }
    # Re-read the complete accepted seal/signing/restore/current-programme
    # closure and protected refs. A caller-authored plan is not authority.
    $promotion = Get-MIR42NineTargetProtectedMainPromotionPlan -RepoRoot $RepoRoot -TechnicalSealPath $TechnicalSealPath -CandidateManifestPath $CandidateManifestPath `
      -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
      -SigningCeremonyPath $SigningCeremonyPath -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath `
      -T16ProtectedRootPath $T16ProtectedRootPath -T16ImmutableAnchorPath $T16ImmutableAnchorPath -T16ApprovedOwnerSid $T16ApprovedOwnerSid -T16ApprovedMutationSids $T16ApprovedMutationSids `
      -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath -OfflineRestoreDrillPath $OfflineRestoreDrillPath
    Get-MIR42NineTargetReleaseAssetInventory -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath -TechnicalSealPath $TechnicalSealPath `
      -PromotionPlan $promotion -SourceVersion $SourceVersion -ReleaseTag $ReleaseTag -AssetRoot $AssetRoot -OutputPath $OutputPath | ConvertTo-Json -Depth 50
  }
  'VerifyBytes' {
    if ([string]::IsNullOrWhiteSpace($FrozenInventoryPath) -or [string]::IsNullOrWhiteSpace($DownloadedAssetRoot)) { throw '[mir42-nine-release-assets-download-inputs-required]' }
    Assert-MIR42NineTargetDownloadedReleaseBytes -FrozenInventoryPath $FrozenInventoryPath -DownloadedAssetRoot $DownloadedAssetRoot | ConvertTo-Json -Depth 30
  }
  'PublicReadback' {
    if ([string]::IsNullOrWhiteSpace($FrozenInventoryPath) -or [string]::IsNullOrWhiteSpace($DownloadedAssetRoot)) { throw '[mir42-nine-release-assets-download-inputs-required]' }
    Get-MIR42NineTargetPublicDownloadedReleaseReadback -FrozenInventoryPath $FrozenInventoryPath -DownloadedAssetRoot $DownloadedAssetRoot | ConvertTo-Json -Depth 30
  }
  'AuthorizePublication' {
    foreach ($path in @($PrimaryRepoRoot,$MaintainerAuthorizationPath,$MainReadbackPath,$FrozenInventoryPath,$OutputPath)) {
      if ([string]::IsNullOrWhiteSpace($path)) { throw '[mir42-nine-release-assets-publication-authorization-inputs-required]' }
    }
    New-MIR42NineTargetPublicationAuthorization -RepoRoot $RepoRoot -PrimaryRepoRoot $PrimaryRepoRoot `
      -MaintainerAuthorizationPath $MaintainerAuthorizationPath -MainReadbackPath $MainReadbackPath `
      -FrozenInventoryPath $FrozenInventoryPath -OutputPath $OutputPath | ConvertTo-Json -Depth 50
  }
}
