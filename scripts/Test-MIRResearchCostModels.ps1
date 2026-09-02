param([string]$RepoRoot = "")

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/compiler/Test-MIRResearchCostModels.ps1"
& $canonicalTest @PSBoundParameters