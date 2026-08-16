param(
  [Parameter(Mandatory)][string]$BeforePath,
  [Parameter(Mandatory)][string]$AfterPath,
  [string]$ApprovalPath = "",
  [Parameter(Mandatory)][string]$OutputPath
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/technology/Compare-MIRTechnologyDesigns.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE