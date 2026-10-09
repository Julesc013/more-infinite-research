# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$runner = Join-Path $repo 'scripts/Invoke-MIRBackportQualification.ps1'
$worktree = Join-Path $repo (Join-Path 'build/results' ("backport-historical-root-rejection-$([Guid]::NewGuid().ToString('N'))"))
$created = $false

try {
  & git -C $repo worktree add --quiet --detach $worktree HEAD | Out-Null
  if ($LASTEXITCODE -ne 0) { throw '[mir4-backport-historical-root-test-worktree-create]' }
  $created = $true
  $failed = $false
  $message = ''
  try {
    & $runner -Action qualify -StaticOnly -HistoricalSourceRoot $worktree | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "[mir4-backport-historical-root-unexpected-exit] $LASTEXITCODE" }
  } catch {
    $failed = $true
    $message = $_.Exception.Message
  }
  if (-not $failed -or $message -notmatch '\[mir-backport-historical-root-commit\]') {
    throw "[mir4-backport-historical-root-clean-checkout-accepted] $message"
  }
  Write-Host '[ok] retired backport qualification rejects an arbitrary clean current checkout before package-root reads.'
} finally {
  if ($created) {
    & git -C $repo worktree remove --force $worktree | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '[mir4-backport-historical-root-test-worktree-remove]' }
  }
}
