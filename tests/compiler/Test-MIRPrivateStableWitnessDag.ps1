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
$runner=Join-Path $repo 'tests/compiler/run_stable_witness_dag_controls.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Private stable witness DAG runner is unavailable: $runner"}
if(-not(Test-Path -LiteralPath $runtime -PathType Container)){throw "Private stable witness DAG Lua runtime is unavailable: $runtime"}

$output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime 2>&1)
if($LASTEXITCODE -ne 0){throw "Private stable witness DAG controls failed: $($output -join [Environment]::NewLine)"}
$recordLine=$output | Where-Object {$_ -match '^\{.*"status": "MIR-PRIVATE-STABLE-WITNESS-DAG-CONTROLS-PASSED".*\}$'} | Select-Object -Last 1
if(-not $recordLine){throw "Private stable witness DAG controls produced no success record: $($output -join [Environment]::NewLine)"}
$record=$recordLine | ConvertFrom-Json
if([int]$record.alias_nodes -ne 3 -or [int]$record.alias_hits -ne 129 -or [int]$record.wide_nodes -ne 429){
  throw 'Private stable witness DAG controls did not retain exact alias/cap traversal counts.'
}
[pscustomobject]@{
  status=[string]$record.status
  assertions=[int]$record.assertions
  alias_nodes=[int]$record.alias_nodes
  alias_hits=[int]$record.alias_hits
  unshared_nodes=[int]$record.unshared_nodes
  wide_nodes=[int]$record.wide_nodes
  source_sha256=[string]$record.source_sha256
  fixture_sha256=[string]$record.fixture_sha256
  runtime=[string]$record.runtime
  factorio_processes=[int]$record.factorio_processes
}
