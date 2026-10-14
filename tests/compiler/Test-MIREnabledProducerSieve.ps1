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
$runner=Join-Path $repo 'tests/compiler/run_enabled_producer_sieve_controls.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Enabled producer sieve runner is unavailable: $runner"}
if(-not(Test-Path -LiteralPath $runtime -PathType Container)){throw "Enabled producer sieve Lua runtime is unavailable: $runtime"}

$output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime 2>&1)
if($LASTEXITCODE -ne 0){throw "Enabled producer sieve controls failed: $($output -join [Environment]::NewLine)"}
$recordLine=$output | Where-Object {$_ -match '^\{.*"status": "MIR-ENABLED-PRODUCER-SIEVE-CONTROLS-PASSED".*\}$'} | Select-Object -Last 1
if(-not $recordLine){throw "Enabled producer sieve controls produced no success record: $($output -join [Environment]::NewLine)"}
$record=$recordLine | ConvertFrom-Json
  if([string]$record.scope -cne 'retired-discovery-characterization-not-current-package-certification'){throw 'Retired discovery controls must remain package-excluded characterizations.'}
if([int]$record.assertions -lt 13 -or [int]$record.cold_sieved -ne 129 -or [int]$record.filtered -ne 5 `
  -or [int]$record.complete -ne 134 -or [int]$record.research_calls -ne 1 -or [int]$record.warm_bucket_reads -ne 1 `
  -or [int]$record.factorio_processes -ne 0){
  throw 'Enabled producer sieve controls did not retain their expected scheduling and callback boundaries.'
}
[pscustomobject]@{
  status=[string]$record.status
  scope=[string]$record.scope
  assertions=[int]$record.assertions
  cold_sieved=[int]$record.cold_sieved
  filtered=[int]$record.filtered
  complete=[int]$record.complete
  research_calls=[int]$record.research_calls
  warm_bucket_reads=[int]$record.warm_bucket_reads
  source_sha256=[string]$record.source_sha256
  fixture_sha256=[string]$record.fixture_sha256
  runtime=[string]$record.runtime
  factorio_processes=[int]$record.factorio_processes
}
