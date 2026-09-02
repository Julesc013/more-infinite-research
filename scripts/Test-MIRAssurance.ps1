param([string]$RepoRoot = "")

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/tooling/Test-MIRAssurance.ps1"
& $canonicalTest @PSBoundParameters