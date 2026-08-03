[CmdletBinding()]
param(
  [string]$RepoRoot = "",
  [string]$OutputPath = "",
  [switch]$Strict,
  [switch]$InventoryOnly,
  [switch]$NoWrite
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
}
. (Join-Path $RepoRoot "tools/lib/workspace/RepoPaths.ps1")

$manifest = New-MIRLayoutManifest -RepoRoot $RepoRoot
if (-not $NoWrite) {
  if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = ".work/output/layout-manifest.json" }
  $absoluteOutput = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
  $parent = Split-Path -Parent $absoluteOutput
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  [IO.File]::WriteAllText($absoluteOutput, (($manifest | ConvertTo-Json -Depth 12) + "`n"), [Text.UTF8Encoding]::new($false))
}

$manifest.summary | ConvertTo-Json -Compress | Write-Output
if (-not $InventoryOnly) {
  if ($manifest.summary.unclassified -ne 0 -or $manifest.summary.case_collisions -ne 0 -or $manifest.summary.links -ne 0) {
    throw "Layout safety check failed: $($manifest.summary | ConvertTo-Json -Compress)"
  }
  if ($Strict -and $manifest.summary.legacy -ne 0) {
    throw "Strict layout check rejects $($manifest.summary.legacy) legacy paths."
  }
}
