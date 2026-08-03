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

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}
$context = New-MIRCPVerificationContext -Mode $Mode -Target $Target -Release $Release -Stage $Stage -CandidatePath $CandidatePath -SourceRepoRoot $SourceRepoRoot -FactorioBin $FactorioBin -OutputRoot $OutputRoot -RepoRoot $repo
$context | ConvertTo-Json -Depth 10
