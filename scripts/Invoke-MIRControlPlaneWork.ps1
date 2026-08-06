param(
  [Parameter(Mandatory)][ValidateSet("record-context", "run-set", "environment", "upgrade", "ecosystem", "approved-delta", "performance", "aggregate")][string]$Operation,
  [Parameter(Mandatory)][string]$ContextPath,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string[]]$Kind = @(),
  [string[]]$ExcludeTask = @(),
  [string]$BatchId = "",
  [string]$FactorioBin = "",
  [string]$PriorRelease = "",
  [string]$LocalModZipDir = "",
  [string]$LocalModDir = "",
  [string]$SourceRepoRoot = "",
  [string]$TrustClass = "ci",
  [string]$AggregateTaskId = "",
  [string]$EvidenceRoot = "build/results/evidence"
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/control/Invoke-MIRControlPlaneWork.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE