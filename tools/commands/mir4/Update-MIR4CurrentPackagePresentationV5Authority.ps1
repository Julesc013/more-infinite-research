[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt = '2026-09-16T12:00:00+10:00',
  [switch]$Check,
  [string]$CheckAuthorityPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
$authorityPath = Join-Path $repo 'spec/distribution/mir4-current-package-presentation-v5.json'
if (-not [string]::IsNullOrWhiteSpace($CheckAuthorityPath)) {
  if (-not $Check) { throw '[mir4-package-presentation-v5-check-path-mode]' }
  $candidate = [IO.Path]::GetFullPath($CheckAuthorityPath)
  $prefix = $repo.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $candidate.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-package-presentation-v5-check-path-boundary]' }
  $authorityPath = $candidate
}
if ($Check) {
  $record = Get-MIR4CurrentPackagePresentationV5 -RepoRoot $repo
  $json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + "`n"
  if (-not (Test-Path -LiteralPath $authorityPath -PathType Leaf) -or [IO.File]::ReadAllText($authorityPath).Replace("`r`n", "`n").Replace("`r", "`n") -cne $json) { throw '[mir4-package-presentation-v5-stale]' }
} elseif (Test-Path -LiteralPath $authorityPath -PathType Leaf) {
  throw '[mir4-package-presentation-v5-authority-immutable-overwrite]'
} else {
  $record = New-MIR4CurrentPackagePresentationV5 -RepoRoot $repo -RecordedAt $RecordedAt
  $json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + "`n"
  [IO.File]::WriteAllText($authorityPath, $json, [Text.UTF8Encoding]::new($false))
}
return $record
