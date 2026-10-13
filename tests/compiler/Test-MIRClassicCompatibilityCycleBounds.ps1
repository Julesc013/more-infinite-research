# MIR4-CONTROLLED-STATIC-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$PythonExe='python',
  [string]$LuaRuntimeDir='build/tmp/mir421-lua-runtime'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$runner=Join-Path $repo 'tests/compiler/run_classic_compatibility_cycle_bounds.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
foreach($path in @($runner,(Join-Path $repo 'source/prototypes/mir/compatibility/repairs/registry.lua'),(Join-Path $repo 'source/prototypes/mir/compatibility/repairs/technology_prerequisite_cycles.lua'),$runtime)){
  if(-not(Test-Path -LiteralPath $path)){throw "Classic compatibility-cycle control input is unavailable: $path"}
}
$output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime 2>&1)
if($LASTEXITCODE-ne0){throw "Classic compatibility-cycle controls failed: $($output-join[Environment]::NewLine)"}
$line=$output|Where-Object{$_-match'^\{.*"status": "MIR-CLASSIC-COMPATIBILITY-CYCLE-BOUNDS-PASSED".*\}$'}|Select-Object -Last 1
if(-not$line){throw "Classic compatibility-cycle controls produced no success record: $($output-join[Environment]::NewLine)"}
$record=$line|ConvertFrom-Json
if([int]$record.assertions-lt18-or[int]$record.factorio_processes-ne0){throw 'Classic compatibility-cycle controls lost opposing coverage.'}
[pscustomobject]@{status=[string]$record.status;assertions=[int]$record.assertions;source_sha256=[string]$record.source_sha256;fixture_sha256=[string]$record.fixture_sha256;runtime=[string]$record.runtime;factorio_processes=[int]$record.factorio_processes}
