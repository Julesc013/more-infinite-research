if (-not (Get-Command Get-MIRPackageSourceRoots -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot "../validation/PackageIdentity.ps1")
}

. (Join-Path $PSScriptRoot 'bootstrap-materialization/DigestsAndRecords.ps1')
. (Join-Path $PSScriptRoot 'bootstrap-materialization/SafePaths.ps1')
. (Join-Path $PSScriptRoot 'bootstrap-materialization/ArchiveComparison.ps1')
. (Join-Path $PSScriptRoot 'bootstrap-materialization/GitSourceProof.ps1')
. (Join-Path $PSScriptRoot 'bootstrap-materialization/CapsuleContract.ps1')
. (Join-Path $PSScriptRoot 'bootstrap-materialization/CapsuleArtifacts.ps1')