param(
  [Parameter(Mandatory)]
  [ValidateSet("0.12", "0.11", "0.10", "0.9", "0.8", "0.7", "0.6")]
  [string]$FactorioVersion,
  [Parameter(Mandatory)][string]$RuntimeProofPath,
  [string]$PackagePath = "",
  [string]$InstallationRoot = "",
  [string]$RegistryPath = "",
  [string]$OutputPath = ""
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/museum/New-MIRMuseumQualification.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE