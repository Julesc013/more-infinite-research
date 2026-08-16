param(
  [string]$RepoRoot = "",
  [switch]$SkipPSScriptAnalyzer
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/tooling/Test-MIRPowerShellQuality.ps1"
& $canonicalTest @PSBoundParameters