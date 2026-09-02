param(
  [ValidateSet("0.12", "0.11", "0.10", "0.9", "0.8", "0.7", "0.6", "all")]
  [string]$FactorioVersion = "all",
  [string]$InstallationRoot = "",
  [string]$RegistryPath = "",
  [int]$TimeoutSeconds = 180
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/runtime/Test-MIRMuseumExact.ps1"
& $canonicalTest @PSBoundParameters