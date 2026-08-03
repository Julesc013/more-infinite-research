param(
  [string]$C24Plan = "artifacts/assurance/plans/verification-plan-c24-full-no-reuse.json",
  [string]$P9Plan = "",
  [switch]$Check,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/control/Update-MIRShadowBaselines.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE