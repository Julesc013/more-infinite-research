param(
  [Parameter(Mandatory)][string]$GroupedFailures,
  [Parameter(Mandatory)][string]$GroupId,
  [string]$OutputPath
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/compatibility/New-MIRCompatProfileStub.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE