param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$Target = "2.1",
  [switch]$Check
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/control/Update-MIRExecutionRegistry.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE