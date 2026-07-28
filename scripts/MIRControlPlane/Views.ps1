function Get-MIRCPCurrentRelease {
  param(
    [ValidateSet("canonical", "backport_calibration")][string]$Role = "canonical",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $policy = Get-MIRCPPolicy -RepoRoot $repo
  $pointer = Read-MIRCPJson -Path ([string]$policy.records.current) -RepoRoot $repo
  $release = [string]$pointer.roles.$Role
  return Read-MIRCPJson -Path ".mir/releases/$release.json" -RepoRoot $repo
}
