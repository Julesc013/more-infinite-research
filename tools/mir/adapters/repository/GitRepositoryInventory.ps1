. (Join-Path $PSScriptRoot '../../domain/repository/RepositoryFixedPoint.ps1')
. (Join-Path $PSScriptRoot '../../ports/repository/RepositoryInventory.ps1')

function Get-MIR4RepositoryInventory {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $repo
  $tracked = @(
    foreach ($path in @(& git -C $repo ls-files)) {
      [ordered]@{path=$path.Replace('\','/');source='git-tracked';class=(Get-MIR4RepositoryPathClass -Path $path)}
    }
  )
  if ($LASTEXITCODE -ne 0) { throw '[mir4-repository-git-tracked]' }
  $ignored = @(
    foreach ($path in @(& git -C $repo ls-files --others --ignored --exclude-standard)) {
      [ordered]@{path=$path.Replace('\','/');source='git-ignored';class=(Get-MIR4RepositoryPathClass -Path $path -Ignored)}
    }
  )
  if ($LASTEXITCODE -ne 0) { throw '[mir4-repository-git-ignored]' }
  $untracked = @(
    foreach ($path in @(& git -C $repo ls-files --others --exclude-standard)) {
      [ordered]@{path=$path.Replace('\','/');source='git-untracked';class=(Get-MIR4RepositoryPathClass -Path $path)}
    }
  )
  if ($LASTEXITCODE -ne 0) { throw '[mir4-repository-git-untracked]' }
  $external = @(
    foreach ($root in @($authority.external_roots)) {
      [ordered]@{environment=[string]$root.environment;path=[string]$root.path;class=[string]$root.class;exists=(Test-Path -LiteralPath ([string]$root.path) -PathType Container)}
    }
  )
  $unknown = @($tracked + $untracked + $ignored | Where-Object { [string]$_.class -eq 'unknown' })
  $inventory = [pscustomobject][ordered]@{
    schema=1
    kind='MIR4RepositoryInventoryV1'
    tracked=$tracked
    untracked=$untracked
    ignored=$ignored
    external=$external
    summary=[ordered]@{tracked=$tracked.Count;untracked=$untracked.Count;ignored=$ignored.Count;external=$external.Count;unknown=$unknown.Count}
    deletion_authorized=$false
  }
  return Assert-MIR4RepositoryInventoryPortV1 -Inventory $inventory
}

function Initialize-MIR4ExternalRepositoryRoots {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $authority = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $RepoRoot
  foreach ($root in @($authority.external_roots)) {
    New-Item -ItemType Directory -Force -Path ([string]$root.path) | Out-Null
    [Environment]::SetEnvironmentVariable([string]$root.environment, [string]$root.path, 'User')
  }
  return Get-MIR4RepositoryInventory -RepoRoot $RepoRoot
}
