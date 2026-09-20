# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'tools/mir/application/package/DistributionCustody.ps1')
. (Join-Path $RepoRoot 'tools/mir/cli/router/MIR4BootstrapCommands.ps1')

if (Test-MIR4DistributionCustodyAliasOwnership -OutputState 'reused') {
  throw 'A valid alias created concurrently after the absence check was misclassified as route-owned.'
}
if (-not (Test-MIR4DistributionCustodyAliasOwnership -OutputState 'materialized-from-verified-cache')) {
  throw 'A route-materialized alias was not classified as route-owned.'
}
$unknownStateRejected = $false
try { Test-MIR4DistributionCustodyAliasOwnership -OutputState 'unknown' | Out-Null }
catch { $unknownStateRejected = $_.Exception.Message -match '\[mir4-distribution-custody-output-state\]' }
if (-not $unknownStateRejected) { throw 'An unknown distribution-custody output state was accepted.' }

function Invoke-CustodyRoute {
  param(
    [Parameter(Mandatory)][string]$TestRepo,
    [Parameter(Mandatory)][string[]]$Arguments
  )
  $mir = Join-Path $TestRepo 'tools/mir.ps1'
  $output = @(& pwsh -NoProfile -File $mir @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) {
    throw "MIR route failed: $($Arguments -join ' ')`n$($output -join [Environment]::NewLine)"
  }
}

$sharedRepo = Get-MIR4DistributionCustodySharedRepoRoot -RepoRoot $RepoRoot
$worktreeParent = [IO.Path]::GetFullPath((Join-Path $sharedRepo 'build/worktrees'))
$testRepo = [IO.Path]::GetFullPath((Join-Path $worktreeParent ('distribution-custody-routes-' + [Guid]::NewGuid().ToString('N'))))
if (-not $testRepo.StartsWith($worktreeParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Distribution-custody route worktree escaped its owned root.'
}
$head = @(& git -C $RepoRoot rev-parse 'HEAD^{commit}')
if ($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or [string]$head[0] -notmatch '^[0-9a-f]{40}$') {
  throw 'Could not resolve the committed source used by the route regression.'
}

$worktreeRegistered = $false
try {
  & git -C $RepoRoot worktree add --detach $testRepo ([string]$head[0]) | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not create the isolated distribution-custody route worktree.' }
  $worktreeRegistered = $true

  $initialArchives = @(Get-ChildItem -LiteralPath (Join-Path $testRepo 'dist') -Filter '*.zip' -File -ErrorAction SilentlyContinue)
  if ($initialArchives.Count -ne 0) { throw 'Isolated distribution-custody route worktree unexpectedly contains local dist archives.' }

  Invoke-CustodyRoute -TestRepo $testRepo -Arguments @('mir4','capture-terminal-baselines','--check')
  Invoke-CustodyRoute -TestRepo $testRepo -Arguments @('mir4','import-terminal-baselines','--check')
  Invoke-CustodyRoute -TestRepo $testRepo -Arguments @('mir4','build-historical-private','--target','F013')
  Invoke-CustodyRoute -TestRepo $testRepo -Arguments @('mir4','check-historical-private','--target','F013')

  $mir = Join-Path $testRepo 'tools/mir.ps1'
  $historicalCandidate = Join-Path $testRepo 'build/mir4/historical-private/distributions/more-infinite-research_4.0.01300.zip'
  $runtimeOutput = @(& pwsh -NoProfile -File $mir mir4 runtime-historical-private --target F013 `
    --factorio-bin $mir --candidate $historicalCandidate 2>&1)
  if ($LASTEXITCODE -eq 0) { throw 'Historical runtime custody regression unexpectedly accepted a non-engine file.' }
  $runtimeText = $runtimeOutput -join [Environment]::NewLine
  if ($runtimeText -match '\[mir4-distribution-custody-' -or
      $runtimeText -match '(?i)cannot find path.+dist[\\/]more-infinite-research') {
    throw "Historical runtime route failed at distribution custody instead of the expected engine-fingerprint boundary.`n$runtimeText"
  }
  if ($runtimeText -notmatch 'engine fingerprint mismatch') {
    throw "Historical runtime route did not reach the expected engine-fingerprint boundary after predecessor resolution.`n$runtimeText"
  }

  $leakedArchives = @(Get-ChildItem -LiteralPath (Join-Path $testRepo 'dist') -Filter '*.zip' -File -ErrorAction SilentlyContinue)
  if ($leakedArchives.Count -ne 0) {
    throw "Clean-checkout MIR routes leaked local distribution aliases: $($leakedArchives.Name -join ', ')"
  }

  $preserved = Restore-MIR4DistributionArchive -RepoRoot $testRepo -Version '3.2.9' -OutputRoot 'dist'
  $preservedDistribution = Get-MIR4DistributionCustodyEntry -RepoRoot $testRepo -Version '3.2.9'
  Invoke-CustodyRoute -TestRepo $testRepo -Arguments @('mir4','capture-terminal-baselines','--check')
  if (-not (Test-MIR4DistributionCustodyFile -Path ([string]$preserved.output_path) -Distribution $preservedDistribution)) {
    throw 'MIR route removed or changed a verified pre-existing local distribution archive.'
  }
}
finally {
  if ($worktreeRegistered) {
    & git -C $RepoRoot worktree remove --force $testRepo | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not remove owned route-regression worktree: $testRepo" }
  }
}

Write-Host '[ok] documented MIR 4 bootstrap routes recover from empty dist, clean aliases, and preserve verified local archives'
