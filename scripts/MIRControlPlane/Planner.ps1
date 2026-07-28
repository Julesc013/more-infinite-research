function Get-MIRCPTaskRecords {
  param([string]$RepoRoot = "")
  return @(Get-MIRCPRecordSet -Kind tasks -RepoRoot $RepoRoot)
}
