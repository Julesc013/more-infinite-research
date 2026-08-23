param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)

$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/RepositoryFixedPoint.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')

$authority = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $RepoRoot
Invoke-MIR4RepositoryRootProjection -RepoRoot $RepoRoot -Check
$inventory = Get-MIR4RepositoryInventory -RepoRoot $RepoRoot
if ([int]$inventory.summary.unknown -ne 0) {
  $paths = @($inventory.tracked + $inventory.untracked + $inventory.ignored | Where-Object class -eq 'unknown' | ForEach-Object path)
  throw "[mir4-w01-unknown-path] $($paths -join ', ')"
}
if ([bool]$inventory.deletion_authorized) { throw '[mir4-w01-deletion-authority]' }

$packageFiles = @(Get-MIRPackageSourceFiles -RepoRoot $RepoRoot)
foreach ($root in @($authority.visible_roots)) {
  $marker = ([string]$root.path) + '/.mir-root.json'
  if ($marker -in $packageFiles) { throw "[mir4-w01-package-visible] $marker" }
}
if (@($authority.visible_roots | Where-Object { $_.mode -like 'shadow*' }).Count -lt 10) { throw '[mir4-w01-shadow-boundary]' }
if (@($authority.move_gate).Count -ne 6 -or [string]$authority.remaining_move.classification -cne 'bounded-shadow-debt') { throw '[mir4-w01-move-gate]' }

Write-Host '[ok] MIR 4 W01 repository shadow fixed point and package firewall passed.'
