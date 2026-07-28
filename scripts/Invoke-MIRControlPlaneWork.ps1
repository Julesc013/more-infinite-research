param(
  [Parameter(Mandatory)][ValidateSet("record-context", "run-set", "environment", "performance", "aggregate")][string]$Operation,
  [Parameter(Mandatory)][string]$ContextPath,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string[]]$Kind = @(),
  [string[]]$ExcludeTask = @(),
  [string]$BatchId = "",
  [string]$FactorioBin = "",
  [string]$PriorRelease = "",
  [string]$LocalModZipDir = "",
  [string]$SourceRepoRoot = "",
  [string]$TrustClass = "ci",
  [string]$EvidenceRoot = "artifacts/evidence"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context", "Executor")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}
switch ($Operation) {
  "record-context" { Write-MIRCPContextCompletionEvidence -ContextPath $ContextPath -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo | ConvertTo-Json -Depth 10 }
  "run-set" { Invoke-MIRCPTaskSet -ContextPath $ContextPath -Kind $Kind -ExcludeTask $ExcludeTask -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -SourceRepoRoot $SourceRepoRoot -RepoRoot $repo | ConvertTo-Json -Depth 10 }
  "environment" { Invoke-MIRCPEnvironmentBatch -ContextPath $ContextPath -BatchId $BatchId -FactorioBin $FactorioBin -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo | ConvertTo-Json -Depth 10 }
  "performance" { Invoke-MIRCPPerformanceMeasurement -ContextPath $ContextPath -FactorioBin $FactorioBin -PriorRelease $PriorRelease -LocalModZipDir $LocalModZipDir -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo | ConvertTo-Json -Depth 10 }
  "aggregate" { Complete-MIRCPAggregateGate -ContextPath $ContextPath -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo | ConvertTo-Json -Depth 10 }
}
