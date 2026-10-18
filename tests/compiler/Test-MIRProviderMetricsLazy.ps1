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
$runner=Join-Path $repo 'tests/compiler/run_provider_metrics_lazy_controls.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Provider metrics lazy control runner is unavailable: $runner"}
if(-not(Test-Path -LiteralPath $runtime -PathType Container)){throw "Provider metrics lazy Lua runtime is unavailable: $runtime"}

$output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime 2>&1)
if($LASTEXITCODE -ne 0){throw "Provider metrics lazy controls failed: $($output -join [Environment]::NewLine)"}
$recordLine=$output | Where-Object {$_ -match '^\{.*"status": "MIR-PROVIDER-METRICS-LAZY-CONTROLS-PASSED".*\}$'} | Select-Object -Last 1
if(-not $recordLine){throw "Provider metrics lazy controls produced no success record: $($output -join [Environment]::NewLine)"}
$record=$recordLine | ConvertFrom-Json
if([string]$record.scope -cne 'host-only-provider-metrics-boundary'){throw 'Provider metrics controls must remain host-only.'}
if([int]$record.assertions -lt 14 -or [int]$record.metric_builds -ne 4){
  throw 'Provider metrics controls did not exercise the normal, inspection, copy, and refusal boundaries.'
}
[pscustomobject]@{
  status=[string]$record.status
  scope=[string]$record.scope
  assertions=[int]$record.assertions
  metric_builds=[int]$record.metric_builds
  resolver_sha256=[string]$record.resolver_sha256
  context_sha256=[string]$record.context_sha256
  publication_sha256=[string]$record.publication_sha256
  fingerprint_sha256=[string]$record.fingerprint_sha256
  provider_metrics_sha256=[string]$record.provider_metrics_sha256
  fixture_sha256=[string]$record.fixture_sha256
  runtime=[string]$record.runtime
  factorio_processes=[int]$record.factorio_processes
}
