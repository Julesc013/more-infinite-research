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
$runner=Join-Path $repo 'tests/runtime/run_settings_catalogue_lifecycle_controls.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Settings catalogue lifecycle runner is unavailable: $runner"}
if(-not(Test-Path -LiteralPath $runtime -PathType Container)){throw "Settings catalogue Lua runtime is unavailable: $runtime"}

$records=@()
foreach($target in @('f200','f210')){
  $output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime --target $target 2>&1)
  if($LASTEXITCODE -ne 0){throw "Settings catalogue lifecycle controls failed for ${target}: $($output -join [Environment]::NewLine)"}
  $line=$output|Where-Object {$_ -match '^{.*"status": "MIR-SETTINGS-CATALOGUE-LIFECYCLE-CONTROLS-PASSED".*}$'}|Select-Object -Last 1
  if(-not $line){throw "Settings catalogue lifecycle controls produced no success record for ${target}: $($output -join [Environment]::NewLine)"}
  $record=$line|ConvertFrom-Json
  if([int]$record.spec_count -lt 1 -or [int]$record.factorio_processes -ne 0){
    throw "Settings catalogue lifecycle controls did not exercise real settings specs for $target."
  }
  $records+=$record
}
[pscustomobject]@{
  status='MIR-SETTINGS-CATALOGUE-LIFECYCLE-CONTROLS-PASSED'
  targets=$records.target
  spec_counts=($records|ForEach-Object { $_.spec_count })
  source_sha256=($records|Select-Object -First 1).source_sha256
  factorio_processes=0
}