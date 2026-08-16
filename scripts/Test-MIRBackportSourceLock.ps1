param([string]$RepoRoot = "")

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/release/Test-MIRBackportSourceLock.ps1"
& $canonicalTest @PSBoundParameters