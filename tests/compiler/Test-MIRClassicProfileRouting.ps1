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
$runner=Join-Path $repo 'tests/compiler/run_classic_profile_routing_controls.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Classic profile routing runner is unavailable: $runner"}
if(-not(Test-Path -LiteralPath $runtime -PathType Container)){throw "Classic profile routing Lua runtime is unavailable: $runtime"}

$records=@()
foreach($target in @('f200','f210')){
  $output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime --target $target 2>&1)
  if($LASTEXITCODE -ne 0){throw "Classic profile routing controls failed for ${target}: $($output -join [Environment]::NewLine)"}
  $line=$output|Where-Object {$_ -match '^{.*"status": "MIR-CLASSIC-PROFILE-ROUTING-CONTROLS-PASSED".*}$'}|Select-Object -Last 1
  if(-not $line){throw "Classic profile routing controls produced no success record for ${target}: $($output -join [Environment]::NewLine)"}
  $record=$line|ConvertFrom-Json
  if([int]$record.assertions -lt 16 -or [int]$record.classic_calls -ne 1 -or [int]$record.full_calls -ne 1 -or [int]$record.historic_full_calls -ne 1 -or [int]$record.factorio_processes -ne 0){
    throw "Classic profile routing controls did not prove both isolated compiler branches for $target."
  }
  $records+=$record
}
[pscustomobject]@{
  status='MIR-CLASSIC-PROFILE-ROUTING-CONTROLS-PASSED'
  targets=$records.target
  assertions=($records|Measure-Object -Property assertions -Sum).Sum
  source_sha256=($records|Select-Object -First 1).source_sha256
  factorio_processes=0
}
