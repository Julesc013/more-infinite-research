param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")),
  [switch]$Check
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/targets/Sync-MIRTargetProfiles.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE