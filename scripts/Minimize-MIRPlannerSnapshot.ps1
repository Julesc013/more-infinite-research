param(
  [Parameter(Mandatory)][string]$InputPath,
  [Parameter(Mandatory)][string[]]$Subjects,
  [Parameter(Mandatory)][string]$OutputPath
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/planner/Minimize-MIRPlannerSnapshot.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE