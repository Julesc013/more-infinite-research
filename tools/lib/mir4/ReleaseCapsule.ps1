Set-StrictMode -Version Latest

if (-not (Get-Command Get-MIR4ArchiveInventory -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'BootstrapMaterialization.ps1')
}
if (-not (Get-Command New-MIR4ComponentInventoryV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'SupplyChain.ps1')
}
if (-not (Get-Command Test-MIR4SupplyChainAttestationV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'SupplyChainAttestation.ps1')
}

$script:MIR4ReleaseCapsuleRootV1 = 'mir4-release-capsule'
$script:MIR4ReleaseCapsuleManifestSchemaV1 = 'spec/schemas/mir4-release-capsule-manifest-v1.schema.json'
$script:MIR4PrivateCustodyInventorySchemaV1 = 'spec/schemas/mir4-private-custody-inventory-v1.schema.json'
$script:MIR4ReleaseCapsuleConstructionSchemaV1 = 'spec/schemas/mir4-release-capsule-construction-receipt-v1.schema.json'
$script:MIR4ReleaseCapsuleRestorationSchemaV1 = 'spec/schemas/mir4-release-capsule-restoration-receipt-v1.schema.json'

. (Join-Path $PSScriptRoot 'release-capsule/CoreRecords.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/CustodyInventory.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/SourceArchiveAndDescriptors.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/SupportRecords.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/ArchiveReadingAndClosure.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/CapsuleConstruction.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/CapsuleVerification.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/CapsuleRestore.ps1')