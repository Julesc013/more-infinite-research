param(
  [ValidateSet('check','initialize')][string]$Command='check',
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [AllowEmptyString()][string]$ArchiveHome='',
  [AllowEmptyString()][string]$PublisherHome='',
  [string]$OutputPath='.mir/local/mir4-release-governance-readiness.json'
)

$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/ReleaseGovernance.ps1')
$result = if ($Command -eq 'initialize') {
  Initialize-MIR4ReleaseGovernanceLayout -RepoRoot $RepoRoot -ArchiveHome $ArchiveHome -PublisherHome $PublisherHome
} else {
  Get-MIR4ReleaseGovernanceReadiness -RepoRoot $RepoRoot -ArchiveHome $ArchiveHome -PublisherHome $PublisherHome
}
$json = ($result | ConvertTo-Json -Depth 20) + "`n"
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $path = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
  New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
  [IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($false))
}
$json
if ([string]$result.classification -eq 'CHANGES-REQUESTED') { exit 1 }
