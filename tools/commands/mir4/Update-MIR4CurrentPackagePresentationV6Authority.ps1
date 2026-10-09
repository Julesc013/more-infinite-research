[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt = '2026-09-21T16:30:00+10:00',
  [ValidateSet(6, 7)]
  [int]$AuthorityVersion = 7,
  [switch]$Check,
  [string]$CheckAuthorityPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
$authorityPath = Join-Path $repo "spec/distribution/mir4-current-package-presentation-v$AuthorityVersion.json"
if (-not [string]::IsNullOrWhiteSpace($CheckAuthorityPath)) {
  if (-not $Check) { throw "[mir4-package-presentation-v$AuthorityVersion-check-path-mode]" }
  $candidate = [IO.Path]::GetFullPath($CheckAuthorityPath)
  $prefix = $repo.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $candidate.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw "[mir4-package-presentation-v$AuthorityVersion-check-path-boundary]" }
  $authorityPath = $candidate
}
if ($Check) {
  $record = if ($AuthorityVersion -eq 6) {
    Get-MIR4CurrentPackagePresentationV6Historical -RepoRoot $repo
  } else {
    Get-MIR4CurrentPackagePresentationV7 -RepoRoot $repo
  }
  $json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + "`n"
  if (-not (Test-Path -LiteralPath $authorityPath -PathType Leaf) -or [IO.File]::ReadAllText($authorityPath).Replace("`r`n", "`n").Replace("`r", "`n") -cne $json) { throw "[mir4-package-presentation-v$AuthorityVersion-stale]" }
} elseif (Test-Path -LiteralPath $authorityPath) {
  throw "[mir4-package-presentation-v$AuthorityVersion-authority-immutable-overwrite]"
} else {
  $record = if ($AuthorityVersion -eq 6) {
    New-MIR4CurrentPackagePresentationV6 -RepoRoot $repo -RecordedAt $RecordedAt
  } else {
    New-MIR4CurrentPackagePresentationV7 -RepoRoot $repo -RecordedAt $RecordedAt
  }
  $json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + "`n"
  [IO.File]::WriteAllText($authorityPath, $json, [Text.UTF8Encoding]::new($false))
}
return $record
