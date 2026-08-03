param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [Parameter(Mandatory)][string[]]$LocalModLibraryDirs,
  [string]$ScenarioPath = "fixtures\compat-matrix\local-library-scenarios.json",
  [int]$MinimumZipCount = 1,
  [string]$OutputPath = "",
  [switch]$Recurse,
  [switch]$AllowMissingScenarioMods
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/compatibility/Test-MIRLocalModLibraryCatalog.ps1"
& $canonicalTest @PSBoundParameters