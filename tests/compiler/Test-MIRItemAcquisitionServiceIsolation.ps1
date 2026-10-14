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
$runner=Join-Path $repo 'tests/compiler/run_item_acquisition_service_controls.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Item acquisition service runner is unavailable: $runner"}
if(-not(Test-Path -LiteralPath $runtime -PathType Container)){throw "Item acquisition service Lua runtime is unavailable: $runtime"}

$output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime 2>&1)
if($LASTEXITCODE -ne 0){throw "Item acquisition service isolation controls failed: $($output -join [Environment]::NewLine)"}
$recordLine=$output | Where-Object {$_ -match '^\{.*"status": "MIR-ITEM-ACQUISITION-SERVICE-ISOLATION-CONTROLS-PASSED".*\}$'} | Select-Object -Last 1
if(-not $recordLine){throw "Item acquisition service isolation controls produced no success record: $($output -join [Environment]::NewLine)"}
$record=$recordLine | ConvertFrom-Json
  if([string]$record.scope -cne 'retired-discovery-characterization-not-current-package-certification'){throw 'Retired discovery controls must remain package-excluded characterizations.'}
if([int]$record.assertions -lt 9 -or [int]$record.calls -ne 5 -or [int]$record.factorio_processes -ne 0){
  throw 'Item acquisition service isolation controls did not retain their expected public-boundary behavior.'
}
[pscustomobject]@{
  status=[string]$record.status
  scope=[string]$record.scope
  assertions=[int]$record.assertions
  calls=[int]$record.calls
  source_sha256=[string]$record.source_sha256
  fixture_sha256=[string]$record.fixture_sha256
  runtime=[string]$record.runtime
  factorio_processes=[int]$record.factorio_processes
}
