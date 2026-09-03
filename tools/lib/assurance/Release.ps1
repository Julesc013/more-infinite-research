. (Join-Path $PSScriptRoot "Hashing.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "validation\ReleaseAttestations.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "mir4\BootstrapMaterialization.ps1")

. (Join-Path $PSScriptRoot 'release/CandidatePlanning.ps1')
. (Join-Path $PSScriptRoot 'release/SealAuthority.ps1')
. (Join-Path $PSScriptRoot 'release/SealCreation.ps1')
. (Join-Path $PSScriptRoot 'release/SealVerification.ps1')