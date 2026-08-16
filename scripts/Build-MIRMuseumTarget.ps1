param(
  [Parameter(Mandatory)]
  [ValidateSet("0.12", "0.11", "0.10", "0.9", "0.8", "0.7", "0.6")]
  [string]$FactorioVersion,
  [string]$OutputDir = "dist",
  [string]$MaterializeRoot = ""
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/museum/Build-MIRMuseumTarget.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE