function Get-MIRCPShadowStatus {
  param([string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $release = Get-MIRCPCurrentRelease -RepoRoot $repo
  return [pscustomobject][ordered]@{
    release = [string]$release.release
    candidate_id = [string]$release.candidate_id
    candidate_sha256 = [string]$release.package.archive_sha256
    status = "shadow-pending"
  }
}

function Assert-MIRCPShadowContract {
  param([string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $authority = Read-MIRCPJson -Path ".mir/control-plane/v4-v5-equivalence.json" -RepoRoot $repo
  $required = @("candidate-identity", "required-proof-obligations", "scenario-identities", "environment-identities", "approved-delta", "upgrade-result", "performance-result", "manual-result", "aggregate-verdict", "seal-inputs")
  if ([int]$authority.schema -ne 1 -or [string]$authority.authority -ne "mir-control-plane-v5-shadow-equivalence") { throw "Shadow equivalence authority is invalid." }
  foreach ($dimension in $required) { if (@($authority.dimensions) -notcontains $dimension) { throw "Shadow authority omits dimension $dimension." } }
  if (@($authority.calibration_candidates) -notcontains "3.2.2" -or @($authority.calibration_candidates) -notcontains "2.5.0") { throw "Shadow authority must cover C24 and P9." }
  if (-not [bool]$authority.acceptance.exact_plan_obligation_equivalence -or -not [bool]$authority.acceptance.exact_verdict_equivalence -or -not [bool]$authority.acceptance.fresh_independent_calibration_required) { throw "Shadow acceptance weakened a required condition." }
  return [pscustomobject][ordered]@{state=[string]$authority.state; dimensions=@($authority.dimensions).Count; candidates=@($authority.calibration_candidates).Count; proofs=@($authority.proofs).Count}
}
