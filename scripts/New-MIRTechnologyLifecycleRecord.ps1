param(
  [Parameter(Mandatory)][ValidateSet("Approval", "Quarantine", "Demotion", "Promotion", "Migration")][string]$Kind,
  [Parameter(Mandatory)][string]$InputPath,
  [Parameter(Mandatory)][string]$OutputPath
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/technology/New-MIRTechnologyLifecycleRecord.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE