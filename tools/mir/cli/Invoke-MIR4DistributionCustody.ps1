param(
  [Parameter(Mandatory)][ValidateSet('status','verify','restore')][string]$Command,
  [Parameter(Mandatory)][string]$RepoRoot,
  [string]$Version,
  [string]$OutputRoot,
  [string]$CacheRoot
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/package/DistributionCustody.ps1')

if ($Command -eq 'status') {
  $manifest = Get-MIR4DistributionCustodyManifest -RepoRoot $repo
  [pscustomobject][ordered]@{
    status=[string]$manifest.status
    distribution_count=[int]$manifest.distribution_count
    custody=$manifest.custody
    release_transition_authority=$false
    publication_authority=$false
  } | ConvertTo-Json -Depth 20
  return
}

if ([string]::IsNullOrWhiteSpace($Version)) { throw "mir4 distribution $Command requires --version." }
$distribution = Get-MIR4DistributionCustodyEntry -RepoRoot $repo -Version $Version
if ($Command -eq 'verify') {
  Test-MIR4DistributionHistoricalCustody -RepoRoot $repo -Distribution $distribution | ConvertTo-Json -Depth 10
  return
}
Restore-MIR4DistributionArchive -RepoRoot $repo -Version $Version -OutputRoot $OutputRoot -CacheRoot $CacheRoot | ConvertTo-Json -Depth 20
