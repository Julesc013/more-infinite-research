# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path,
  [string]$LuaRuntimeDir = (Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path 'build/tmp/mir421-lua-runtime'),
  [string]$PythonExe = 'python'
)
$ErrorActionPreference = 'Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$upgradeRunner=Get-Content -LiteralPath (Join-Path $repo 'tests/runtime/Test-MIRUpgrade.ps1') -Raw
if($upgradeRunner.Contains('PersistentFixtureNames')){throw '[mir47-k2-owned-speed-sentinel-public-fixture-selector]'}
if(-not$upgradeRunner.Contains('Get-MIR470K2OwnedSpeedSentinelFixture')){throw '[mir47-k2-owned-speed-sentinel-internal-selection]'}
. (Join-Path $repo 'tests/support/MIR421K2Upgrade.ps1')
$fixture=Get-MIR470K2OwnedSpeedSentinelFixture -RepoRoot $repo -FixtureName 'assert-upgrade-k2-imersite-4-6-21000-to-4-7-21000' -SourceVersion '4.7.0'
if($fixture.name-cne'aaa-mir47-owned-speed-sentinel'-or-not$fixture.info_sha256-or-not$fixture.control_sha256){throw '[mir47-k2-owned-speed-sentinel-record]'}
try { Get-MIR470K2OwnedSpeedSentinelFixture -RepoRoot $repo -FixtureName 'other' -SourceVersion '4.7.0'|Out-Null;throw '[mir47-k2-owned-speed-sentinel-wrong-fixture-accepted]' }catch{
  if($_.Exception.Message-ne'[mir470-k2-owned-speed-sentinel-fixture-admission]'){throw}
}$runtime=(Resolve-Path -LiteralPath $LuaRuntimeDir).Path
$runner=Join-Path $repo 'tests/runtime/run_k2_owned_speed_sentinel_controls.py'
$output=Join-Path $repo 'build/tmp/mir47-k2-owned-speed-sentinel-controls-v2.json'
$result=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime --output $output 2>&1)
if($LASTEXITCODE-ne0){throw ($result -join [Environment]::NewLine)}
$receipt=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json -Depth 20
if($receipt.status-cne'passed'-or[bool]$receipt.factorio_invoked-or[int]$receipt.assertions-lt1){throw '[mir47-k2-owned-speed-sentinel-controls-receipt]'}
Write-Host "[ok] MIR 4.7 K2 owned speed sentinel host controls passed: $output"
