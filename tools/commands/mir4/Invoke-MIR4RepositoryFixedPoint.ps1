param(
  [ValidateSet('generate','check','inventory','initialize')][string]$Command='check',
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputPath=''
)

$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/RepositoryFixedPoint.ps1')

if ($Command -eq 'generate') { Invoke-MIR4RepositoryRootProjection -RepoRoot $RepoRoot }
if ($Command -eq 'check') { Invoke-MIR4RepositoryRootProjection -RepoRoot $RepoRoot -Check }
$inventory = if ($Command -eq 'initialize') {
  Initialize-MIR4ExternalRepositoryRoots -RepoRoot $RepoRoot
} else {
  Get-MIR4RepositoryInventory -RepoRoot $RepoRoot
}
if ([int]$inventory.summary.unknown -ne 0) { throw '[mir4-repository-inventory-unknown]' }
$authority = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $RepoRoot
$result = [ordered]@{
  schema=1
  kind='MIR4RepositoryFixedPointResultV1'
  programme_id=[string]$authority.programme_id
  classification=[string]$authority.state
  physical_cutover=[bool]$authority.physical_cutover
  current_package_source_remains_authoritative=[bool]$authority.current_package_source_remains_authoritative
  inventory=$inventory.summary
  external_roots=$inventory.external
  visible_roots=@($authority.visible_roots | ForEach-Object { [ordered]@{id=[string]$_.id;path=[string]$_.path;mode=[string]$_.mode} })
  remaining_move=$authority.remaining_move
  deletion_authorized=$false
  publication_authorized=$false
}
$json = ($result | ConvertTo-Json -Depth 30) + "`n"
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $path = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
  New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
  [IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($false))
}
$json
