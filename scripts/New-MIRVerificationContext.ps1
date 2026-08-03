param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [ValidateSet("changed", "qualify-incremental", "calibrate-fresh", "rerun-failure")][string]$Mode = "qualify-incremental",
  [string]$Target = "2.1",
  [string]$Release = "",
  [ValidateSet("verification", "release", "publication", "all")][string]$Stage = "verification",
  [string]$CandidatePath = "",
  [string]$SourceRepoRoot = "",
  [string]$FactorioBin = "",
  [string]$OutputRoot = ".work/output/verification-context"
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/control/New-MIRVerificationContext.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE