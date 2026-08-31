param(
  [ValidateSet('run', 'check')][string]$Command = 'run',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputPath = 'build/reports/release-rehearsal/M40-01/rehearsal.json'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\application\release\PatchLaneRehearsal.ps1')

$record = Invoke-MIR4PatchLaneRehearsalV1 -RepoRoot $RepoRoot
$json = ($record | ConvertTo-Json -Depth 100) + [char]10
$output = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }

if ($Command -eq 'check' -and (Test-Path -LiteralPath $output -PathType Leaf)) {
  $existing = [IO.File]::ReadAllText($output)
  if ($existing -cne $json) { throw "[mir4-patch-rehearsal-output-drift] $OutputPath" }
} else {
  $parent = Split-Path -Parent $output
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  [IO.File]::WriteAllText($output, $json, [Text.UTF8Encoding]::new($false))
}

$json
