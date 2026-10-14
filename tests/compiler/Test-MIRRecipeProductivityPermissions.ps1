# MIR4-CONTROLLED-STATIC-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$PythonExe='python',
  [string]$LuaRuntimeDir='build/tmp/mir421-lua-runtime'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$runner=Join-Path $repo 'tests/compiler/run_recipe_productivity_permissions_controls.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Productivity-permission runner is unavailable: $runner"}
if(-not(Test-Path -LiteralPath $runtime -PathType Container)){throw "Productivity-permission Lua runtime is unavailable: $runtime"}

$output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime 2>&1)
if($LASTEXITCODE -ne 0){throw "Productivity-permission controls failed: $($output -join [Environment]::NewLine)"}
$recordLine=$output | Where-Object {$_ -match '^\{.*"status": "MIR-RECIPE-PRODUCTIVITY-PERMISSIONS-CONTROLS-PASSED".*\}$'} | Select-Object -Last 1
if(-not$recordLine){throw "Productivity-permission controls produced no success record: $($output -join [Environment]::NewLine)"}
$record=$recordLine | ConvertFrom-Json
if (
  [int]$record.assertions -lt 4 -or
  [int]$record.published_baseline_assertions -lt 14 -or
  [int]$record.implicit_admission_absent_assertions -lt 1 -or
  [int]$record.pipeline_assertions -lt 14 -or
  [int]$record.factorio_processes -ne 0
){
  throw 'Productivity-permission controls did not retain the published mining-emission, no-new-drill-permission, and existing Space Age permission boundaries.'
}
[pscustomobject]@{
  status=[string]$record.status
  assertions=[int]$record.assertions
  pipeline_sha256=[string]$record.pipeline_sha256
  streams_sha256=[string]$record.streams_sha256
  published_baseline_assertions=[int]$record.published_baseline_assertions
  fixture_sha256=[string]$record.fixture_sha256
  published_baselines=$record.published_baselines
  runtime=[string]$record.runtime
  factorio_processes=[int]$record.factorio_processes
}
