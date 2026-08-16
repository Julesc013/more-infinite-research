param(
  [Parameter(Mandatory)][string[]]$AuditLogPaths,
  [Parameter(Mandatory)][string]$TargetProfile,
  [string]$SourceCommit = "",
  [string]$ArchiveSha256 = "",
  [Parameter(Mandatory)][string]$OutputPath
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/planner/Export-MIRPlannerSnapshot.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE