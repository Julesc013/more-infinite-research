param(
  [Parameter(Mandatory)][string]$CatalogPath,
  [string]$EvidencePath,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [ValidateRange(1, 500)][int]$Top = 50
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/technology/Export-MIRCompilerPreview.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE