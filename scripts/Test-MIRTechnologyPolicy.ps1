param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")))

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/compiler/Test-MIRTechnologyPolicy.ps1"
& $canonicalTest @PSBoundParameters