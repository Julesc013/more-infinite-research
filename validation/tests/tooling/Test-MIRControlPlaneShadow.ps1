param(
  [string]$ContextPath = "",
  [string]$SourceRepoRoot = "",
  [string]$EvidenceRoot = ".work/artifacts/evidence",
  [switch]$ContractOnly,
  [switch]$StructuralOnly,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context", "Shadow")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}
$shadow = if ($StructuralOnly) { $null } else { Assert-MIRCPShadowContract -RepoRoot $repo }
if ($ContractOnly) {
  Write-Host "[ok] v4/v5 shadow contract covers $($shadow.dimensions) dimensions and $($shadow.candidates) candidates; analysis is $($shadow.analysis_status) with $(@($shadow.pending).Count) pending rows."
  exit 0
}
if ([string]::IsNullOrWhiteSpace($ContextPath) -or [string]::IsNullOrWhiteSpace($SourceRepoRoot)) {
  throw "Operational shadow evaluation requires one immutable context and exact source checkout."
}
$manifest = Get-Content -Raw -LiteralPath (Join-Path (Resolve-Path -LiteralPath $ContextPath).Path "context-manifest.json") | ConvertFrom-Json
$releaseRecord = Get-MIRCPReleaseByVersion -Release ([string]$manifest.release) -RepoRoot $repo
$authority = Get-MIRCPShadowAuthority -RepoRoot $repo
$isCalibrationCandidate = [string]$manifest.release -in @($authority.calibration_candidates | ForEach-Object { [string]$_ })
if (-not $isCalibrationCandidate) {
  $inherited = Assert-MIRCPInheritedShadowCutover -ReleaseRecord $releaseRecord -ContextPath $ContextPath -SourceRepoRoot $SourceRepoRoot -RepoRoot $repo
  if (-not $StructuralOnly) {
    [void](Assert-MIRCPInheritedReleaseProofClosure -ReleaseRecord $releaseRecord -ContextPath $ContextPath -EvidenceRoot $EvidenceRoot -RepoRoot $repo)
  }
  Write-Host "[ok] inherited v4/v5 shadow cutover is accepted for $($manifest.release) from $($inherited.calibration_release)."
  exit 0
}
$candidate = New-MIRCPShadowCandidateAnalysis -Release ([string]$manifest.release) -SourceRepoRoot $SourceRepoRoot -ContextPath $ContextPath -EvidenceRoot $EvidenceRoot -RepoRoot $repo
foreach ($dimension in @("candidate-identity", "required-proof-obligations", "scenario-identities", "environment-identities")) {
  if ([string]$candidate.dimensions.$dimension.status -ne "passed") { throw "Shadow structural dimension failed for $($manifest.release): $dimension" }
}
if ($StructuralOnly) {
  Write-Host "[ok] exact v4/v5 structural shadow equivalence passed for $($manifest.release)."
  exit 0
}
if ([string]$candidate.status -ne "passed") { throw "Candidate shadow verdict is incomplete: $(@($candidate.pending_dimensions) -join ', ')." }
$analysis = Read-MIRCPJson -Path ".mir/control-plane/shadow-analysis.json" -RepoRoot $repo
$c24 = @($analysis.candidates | Where-Object release -eq "3.2.2")
if ($c24.Count -ne 1 -or [string]$c24[0].status -ne "passed") { throw "Committed C24 historical shadow comparison is incomplete." }
Write-Host "[ok] exact v4/v5 shadow equivalence is accepted for $($manifest.release)."
