function Get-MIRCPEvidenceRoot {
  param([string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $policy = Get-MIRCPPolicy -RepoRoot $repo
  return Join-Path $repo ([string]$policy.outputs.evidence_store)
}
