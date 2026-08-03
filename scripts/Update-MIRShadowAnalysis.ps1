param(
  [Parameter(Mandatory)][string]$C24SourceRepoRoot,
  [Parameter(Mandatory)][string]$P9SourceRepoRoot,
  [string]$P9ObservedProofRoot = "",
  [switch]$Check,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/control/Update-MIRShadowAnalysis.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE