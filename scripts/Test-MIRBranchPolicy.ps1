param(
  [switch]$SkipFetch
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/release/Test-MIRBranchPolicy.ps1"
& $canonicalTest @PSBoundParameters