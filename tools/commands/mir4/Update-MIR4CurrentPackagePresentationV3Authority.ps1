[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [switch]$Check,
  [string]$CheckAuthorityPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')

# V3 is append-only historical evidence. Its old current-source binding is
# intentionally never regenerated after the Factorio-1 convergence successor.
$record = Get-MIR4CurrentPackagePresentationV3Historical -RepoRoot $repo
$json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + "`n"
$path = Join-Path $repo 'spec/distribution/mir4-current-package-presentation-v3.json'
if (-not [string]::IsNullOrWhiteSpace($CheckAuthorityPath)) {
  if (-not $Check) { throw '[mir4-package-presentation-v3-historical-check-path-mode]' }
  $candidate = [IO.Path]::GetFullPath($CheckAuthorityPath)
  $prefix = $repo.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $candidate.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-package-presentation-v3-historical-check-path-boundary]' }
  $path = $candidate
}
if (-not $Check) { throw '[mir4-package-presentation-v3-historical-write-retired]' }
if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n") -cne $json) { throw '[mir4-package-presentation-v3-historical-stale]' }
return [pscustomobject][ordered]@{status='historical-current';path='spec/distribution/mir4-current-package-presentation-v3.json';record_sha256=[string]$record.record_sha256;release_authority=$false}
