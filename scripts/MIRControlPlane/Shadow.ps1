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
