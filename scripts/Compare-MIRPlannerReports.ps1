param(
  [Parameter(Mandatory)][string]$Before,
  [Parameter(Mandatory)][string]$After,
  [string]$OutputPath = ""
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/planner/Compare-MIRPlannerReports.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE