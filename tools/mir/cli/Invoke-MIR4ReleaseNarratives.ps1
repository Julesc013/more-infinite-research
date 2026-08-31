param(
  [ValidateSet('render','check')][string]$Command = 'render',
  [Parameter(Mandatory)][string]$Plan,
  [Parameter(Mandatory)][string]$Output,
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/mir/domain/canonicalization/CanonicalJsonV1.ps1')
. (Join-Path $PSScriptRoot '../application/release/ReleaseNarratives.ps1')
$result = Invoke-MIR4ReleaseNarrativesV1 -RepoRoot $RepoRoot -PlanPath $Plan -OutputRoot $Output -Command $Command
$result | ConvertTo-Json -Depth 100
