param(
  [Parameter(Position=0)][ValidateSet("help", "validate", "package-freeze", "baseline", "status", "views", "plan", "registry", "replay", "context", "evidence-index", "aggregate", "calibrate", "calibration-proof", "qualification", "release", "backport", "seal", "promotion")][string]$Command = "help",
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [switch]$AllLocks,
  [switch]$Check,
  [ValidateSet("changed", "qualify-incremental", "calibrate-fresh", "rerun-failure")][string]$Mode = "changed",
  [string]$ChangedSince = "",
  [string[]]$ChangedPath = @(),
  [string[]]$FailedTask = @(),
  [string]$EvidenceIndex = "",
  [string]$TrustClass = "ci",
  [string]$Target = "2.1",
  [string]$Release = "",
  [ValidateSet("verification", "release", "publication", "all")][string]$Stage = "verification",
  [string]$Output = ".work/output/control-plane-v5-plan.json",
  [string]$ContextOutputRoot = ".work/output/verification-context",
  [string]$EvidenceRoot = "",
  [string]$ContextPath = "",
  [string]$AggregateTaskId = "",
  [string]$TaskId = "",
  [string]$CandidatePath = "",
  [string]$SourceRepoRoot = "",
  [string]$FactorioBin = "",
  [string]$PriorRelease = "",
  [string]$LocalModDir = "",
  [string]$LocalModZipDir = "",
  [switch]$Resume
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/control/Invoke-MIRControlPlane.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE