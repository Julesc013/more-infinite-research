param(
  [ValidateSet('render','check','source-render','source-check')][string]$Command = 'render',
  [Parameter(Mandatory)][string]$Plan,
  [string]$Output = '',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/mir/domain/canonicalization/CanonicalJsonV1.ps1')
. (Join-Path $PSScriptRoot '../application/release/ReleaseNarratives.ps1')
$result = if ($Command -in @('source-render','source-check')) {
  Update-MIR4SourceChangelogV1 -RepoRoot $RepoRoot -PlanPath $Plan -Check:($Command -eq 'source-check')
} else {
  if ([string]::IsNullOrWhiteSpace($Output)) { throw '[mir4-release-narrative-output-required]' }
  Invoke-MIR4ReleaseNarrativesV1 -RepoRoot $RepoRoot -PlanPath $Plan -OutputRoot $Output -Command $Command
}
$result | ConvertTo-Json -Depth 100
