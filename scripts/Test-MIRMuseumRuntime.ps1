param(
  [Parameter(Mandatory)]
  [ValidateSet("0.12", "0.11", "0.10", "0.9", "0.8", "0.7", "0.6")]
  [string]$FactorioVersion,
  [ValidateSet("directory", "zip")]
  [string]$PackageMode = "directory",
  [switch]$OneTechnology,
  [switch]$Reload,
  [string]$PackagePath = "",
  [string]$InstallationRoot = "",
  [string]$RegistryPath = "",
  [int]$TimeoutSeconds = 180,
  [string]$EvidenceRoot = ""
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/runtime/Test-MIRMuseumRuntime.ps1"
& $canonicalTest @PSBoundParameters