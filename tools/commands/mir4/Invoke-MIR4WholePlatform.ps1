param(
  [Parameter(Mandatory)][ValidateSet('generate', 'check', 'matrix', 'target-key')][string]$Command,
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')),
  [string]$Target
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/platform/WholePlatform.ps1')

switch ($Command) {
  'generate' {
    $path = Invoke-MIR4WholePlatformProjection -RepoRoot $RepoRoot
    Write-Host "[ok] MIR 4 whole-platform matrix generated: $path"
  }
  'check' {
    $matrix = Test-MIR4WholePlatformProgramme -RepoRoot $RepoRoot
    Write-Host "[ok] MIR 4 whole-platform consolidation passed: areas=$($matrix.area_count) destination=4.0.0"
  }
  'matrix' {
    Get-MIR4WholePlatformMatrix -RepoRoot $RepoRoot | ConvertTo-Json -Depth 100
  }
  'target-key' {
    if ([string]::IsNullOrWhiteSpace($Target)) { throw 'target-key requires -Target FNNN.' }
    New-MIR4TargetKeyProjection -Target $Target | ConvertTo-Json -Depth 10
  }
}
