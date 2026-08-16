[CmdletBinding()]
param(
  [string]$RepoRoot = "",
  [string]$Id = "",
  [string]$Path = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
}
. (Join-Path $RepoRoot "tools/lib/workspace/RepoPaths.ps1")

if (-not [string]::IsNullOrWhiteSpace($Id) -and -not [string]::IsNullOrWhiteSpace($Path)) {
  throw "Specify either -Id or -Path, not both."
}
if (-not [string]::IsNullOrWhiteSpace($Id)) {
  Resolve-MIRRepoPath -RepoRoot $RepoRoot -Id $Id | ConvertTo-Json
} elseif (-not [string]::IsNullOrWhiteSpace($Path)) {
  Resolve-MIRRepoPath -RepoRoot $RepoRoot -Path $Path | ConvertTo-Json
} else {
  throw "Specify -Id or -Path."
}
