param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$PolicyPath = ".mir\sanitation-budgets.json"
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/release/Test-MIRSanitationBudgets.ps1"
& $canonicalTest @PSBoundParameters