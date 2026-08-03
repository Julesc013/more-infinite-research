[CmdletBinding()]
param(
    [switch]$Index
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1"
& $canonicalTest @PSBoundParameters