param(
  [string]$PolicyPath = ".mir\mod-interaction-policy.json",
  [string]$OutputPath = ".mir\mod-interaction-graph.json"
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/compatibility/New-MIRModInteractionGraph.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE