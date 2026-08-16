param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string[]]$Paths = @(),
  [switch]$Check
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/docs/Format-MIRMarkdown.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE