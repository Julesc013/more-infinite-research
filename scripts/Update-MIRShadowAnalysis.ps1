param(
  [Parameter(Mandatory)][string]$C24SourceRepoRoot,
  [Parameter(Mandatory)][string]$P9SourceRepoRoot,
  [string]$P9ObservedProofRoot = "",
  [switch]$Check,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context", "Shadow")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}
$authorityPath = Join-Path $repo ".mir/control-plane/v4-v5-equivalence.json"
$c24 = New-MIRCPShadowCandidateAnalysis -Release "3.2.2" -SourceRepoRoot $C24SourceRepoRoot -RepoRoot $repo
$p9 = New-MIRCPShadowCandidateAnalysis -Release "2.5.0" -SourceRepoRoot $P9SourceRepoRoot -ObservedProofRoot $P9ObservedProofRoot -RepoRoot $repo
$candidates = @($c24, $p9)
$pending = @($candidates | ForEach-Object {
  $release = [string]$_.release
  @($_.pending_dimensions | ForEach-Object { "$release/$_" })
} | Sort-Object)
$body = [pscustomobject][ordered]@{
  schema = 1
  authority = "mir-control-plane-v5-shadow-analysis"
  authority_sha256 = Get-MIRCPSha256File -Path $authorityPath
  status = if ($pending.Count -eq 0) { "passed" } else { "pending" }
  pending_dimensions = $pending
  candidates = $candidates
}
$record = [ordered]@{}
foreach ($property in $body.PSObject.Properties) { $record[$property.Name] = $property.Value }
$record.analysis_sha256 = Get-MIRCPSha256Object -Value $body
Write-MIRCPJson -Path ".mir/control-plane/shadow-analysis.json" -Value ([pscustomobject]$record) -RepoRoot $repo -Check:$Check
[pscustomobject][ordered]@{status=if($Check){"current"}else{"updated"};analysis=[string]$body.status;pending=$pending.Count;sha256=[string]$record.analysis_sha256} | ConvertTo-Json
