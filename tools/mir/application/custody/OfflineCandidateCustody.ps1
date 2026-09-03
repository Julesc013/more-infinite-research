# R0 proof-only custody. This library never grants publication authority and all
# key material and generated evidence must remain below ignored local roots.
$bootstrapMaterialization = Join-Path $PSScriptRoot "../../../lib/mir4/BootstrapMaterialization.ps1"
if (-not (Test-Path -LiteralPath $bootstrapMaterialization -PathType Leaf)) {
  throw "The MIR 4 bootstrap record authority is missing: $bootstrapMaterialization"
}
. $bootstrapMaterialization

$distributionIdentityAuthority = Join-Path $PSScriptRoot "../../../lib/validation/MIR4DistributionIdentity.ps1"
if (-not (Test-Path -LiteralPath $distributionIdentityAuthority -PathType Leaf)) {
  throw "The MIR 4 distribution identity authority is missing: $distributionIdentityAuthority"
}
. $distributionIdentityAuthority

$script:MIR4BootstrapCanonicalizationV1 = "MIR4BootstrapCanonicalJsonV1"
$script:MIR4OfflineSealNamespaceV1 = "mir4-offline-candidate-seal-v1"
$script:MIR4ExactEngineEvidenceNamespaceV1 = "mir4-exact-engine-qualification-v1"
$script:MIR4ExactEngineObservationIdsV1 = @(
  "clean-install",
  "direct-upgrade-from-3.2.11",
  "reload-after-upgrade-1",
  "reload-after-upgrade-2",
  "settings-profile-state-preservation",
  "target-compatibility"
)

$script:MIR4OfflineCustodyApplicationRootV1 = $PSScriptRoot
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/CoreRecords.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/Admission.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/SealInputs.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/OpenSshSignatures.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/ExactEngineEvidence.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/PublicationDryRun.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/OfflineSeal.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/RestoreAndCompletion.ps1')