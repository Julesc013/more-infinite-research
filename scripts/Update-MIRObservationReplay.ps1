param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [switch]$Check
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "scripts/MIRControlPlane/Core.ps1")
. (Join-Path $repo "scripts/MIRControlPlane/Scenario.ps1")
. (Join-Path $repo "scripts/MIRControlPlane/Observation.ps1")
$report = Update-MIRCPV4ReplayReport -RepoRoot $repo -Check:$Check
if ([string]$report.verdict -ne "passed") { throw "Historical observation replay failed." }
Write-Host "[ok] replayed $($report.metrics.source_evidence) v4 evidence rows as independently keyed observations and offline evaluations ($($report.replay_sha256))."
