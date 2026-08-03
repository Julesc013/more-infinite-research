param(
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9._-]*$')][string]$Id,
  [Parameter(Mandatory)][string]$ModId,
  [string]$Version = "*",
  [ValidateSet("2.0", "2.1")][string[]]$FactorioLines = @("2.1"),
  [Parameter(Mandatory)][string]$OutputPath
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/planner/New-MIRCompatibilityPack.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE