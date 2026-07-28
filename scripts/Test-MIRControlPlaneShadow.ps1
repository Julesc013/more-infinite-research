param(
  [string]$ContextPath = "",
  [string]$SourceRepoRoot = "",
  [switch]$ContractOnly,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context", "Shadow")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}
$shadow = Assert-MIRCPShadowContract -RepoRoot $repo
if ($ContractOnly) {
  Write-Host "[ok] v4/v5 shadow contract covers $($shadow.dimensions) dimensions and $($shadow.candidates) candidates; analysis is $($shadow.analysis_status) with $(@($shadow.pending).Count) pending rows."
  exit 0
}
if ([string]::IsNullOrWhiteSpace($ContextPath) -or [string]::IsNullOrWhiteSpace($SourceRepoRoot)) {
  throw "Operational shadow evaluation requires one immutable context and exact source checkout."
}
$manifest = Get-Content -Raw -LiteralPath (Join-Path (Resolve-Path -LiteralPath $ContextPath).Path "context-manifest.json") | ConvertFrom-Json
$candidate = New-MIRCPShadowCandidateAnalysis -Release ([string]$manifest.release) -SourceRepoRoot $SourceRepoRoot -ContextPath $ContextPath -RepoRoot $repo
foreach ($dimension in @("candidate-identity", "required-proof-obligations", "scenario-identities", "environment-identities")) {
  if ([string]$candidate.dimensions.$dimension.status -ne "passed") { throw "Shadow structural dimension failed for $($manifest.release): $dimension" }
}
if ([string]$shadow.state -ne "accepted") {
  throw "v4/v5 shadow cutover remains pending: $(@($shadow.pending) -join ', ')."
}
if ([string]$candidate.status -ne "passed") { throw "Candidate shadow verdict is incomplete: $(@($candidate.pending_dimensions) -join ', ')." }
Write-Host "[ok] exact v4/v5 shadow equivalence is accepted for $($manifest.release)."
