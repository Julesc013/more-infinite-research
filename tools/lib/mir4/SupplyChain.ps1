if (-not (Get-Command ConvertTo-MIR4BootstrapCanonicalJson -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'BootstrapMaterialization.ps1')
}

$script:MIR4SupplyChainAuthorityPath = '.mir/releases/governance/mir4/supply-chain.json'
$script:MIR4SupplyChainAuthoritySchemaPath = 'spec/schemas/mir4-supply-chain-authority-v1.schema.json'
$script:MIR4ComponentInventorySchemaPath = 'spec/schemas/mir4-component-inventory-v1.schema.json'
$script:MIR4SpdxProfileSchemaPath = 'spec/schemas/mir4-spdx-3.0.1-profile.schema.json'
$script:MIR4Spdx2ProfileSchemaPath = 'spec/schemas/mir4-spdx-2.3-compatibility.schema.json'
$script:MIR4SlsaProfileSchemaPath = 'spec/schemas/mir4-slsa-provenance-v1.schema.json'

. (Join-Path $PSScriptRoot 'supply-chain/CoreAndRows.ps1')
. (Join-Path $PSScriptRoot 'supply-chain/ArchiveAndSelection.ps1')
. (Join-Path $PSScriptRoot 'supply-chain/ComponentInventory.ps1')
. (Join-Path $PSScriptRoot 'supply-chain/SpdxAttestation.ps1')
. (Join-Path $PSScriptRoot 'supply-chain/ProvenanceAndVerification.ps1')