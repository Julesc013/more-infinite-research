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
$runner=Join-Path $repo 'tests/runtime/run_classic_profile_notice_controls.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Classic profile notice runner is unavailable: $runner"}
if(-not(Test-Path -LiteralPath $runtime -PathType Container)){throw "Classic profile notice Lua runtime is unavailable: $runtime"}
$output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime 2>&1)
if($LASTEXITCODE -ne 0){throw "Classic profile notice controls failed: $($output -join [Environment]::NewLine)"}
$line=$output|Where-Object {$_ -match '^{.*"status": "MIR-CLASSIC-PROFILE-NOTICE-CONTROLS-PASSED".*}$'}|Select-Object -Last 1
if(-not $line){throw "Classic profile notice controls produced no success record: $($output -join [Environment]::NewLine)"}
$record=$line|ConvertFrom-Json
if([int]$record.assertions -lt 13 -or [int]$record.factorio_processes -ne 0){throw 'Classic profile notice controls did not prove the required lifecycle behavior.'}
$record