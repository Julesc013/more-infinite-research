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
$runner=Join-Path $repo 'tests/compiler/run_witness_memo_controls.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Witness memo control runner is unavailable: $runner"}
if(-not(Test-Path -LiteralPath $runtime -PathType Container)){throw "Witness memo Lua runtime is unavailable: $runtime"}

$output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime 2>&1)
if($LASTEXITCODE -ne 0){throw "Witness memo isolation controls failed: $($output -join [Environment]::NewLine)"}
$recordLine=$output | Where-Object {$_ -match '^\{.*"status": "MIR-WITNESS-MEMO-ISOLATION-CONTROLS-PASSED".*\}$'} | Select-Object -Last 1
if(-not $recordLine){throw "Witness memo isolation controls produced no success record: $($output -join [Environment]::NewLine)"}
$record=$recordLine | ConvertFrom-Json
  if([string]$record.scope -cne 'retired-discovery-characterization-not-current-package-certification'){throw 'Retired discovery controls must remain package-excluded characterizations.'}
if([int]$record.private_hits -ne 3 -or [int]$record.isolated_hits -ne 2 -or [int]$record.graph_clone_calls -ne 2){
  throw 'Witness memo isolation controls did not retain their expected cold/warm operation counts.'
}
[pscustomobject]@{
  status=[string]$record.status
  scope=[string]$record.scope
  assertions=[int]$record.assertions
  private_hits=[int]$record.private_hits
  isolated_hits=[int]$record.isolated_hits
  graph_clone_calls=[int]$record.graph_clone_calls
  source_sha256=[string]$record.source_sha256
  fixture_sha256=[string]$record.fixture_sha256
  runtime=[string]$record.runtime
  factorio_processes=[int]$record.factorio_processes
}
