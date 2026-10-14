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
  [int]$record.assertions -lt 13 -or
  [int]$record.descriptor_assertions -lt 1 -or
  [int]$record.pipeline_assertions -lt 5 -or
  [int]$record.factorio_processes -ne 0
){
  throw 'Productivity-permission controls did not retain the implicit-only, descriptor, effect-emission, and upstream-policy boundaries.'
}
[pscustomobject]@{
  status=[string]$record.status
  assertions=[int]$record.assertions
  pipeline_sha256=[string]$record.pipeline_sha256
  streams_sha256=[string]$record.streams_sha256
  descriptor_sha256=[string]$record.descriptor_sha256
  fixture_sha256=[string]$record.fixture_sha256
  runtime=[string]$record.runtime
  factorio_processes=[int]$record.factorio_processes
}
