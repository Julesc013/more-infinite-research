param(
  [string]$OutputDir = "dist",
  [ValidateSet("Fastest", "NoCompression", "Optimal")]
  [string]$CompressionLevel = "Optimal"
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/package/Build-MIRPackage.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE