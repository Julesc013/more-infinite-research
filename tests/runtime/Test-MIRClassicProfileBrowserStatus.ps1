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
$runner=Join-Path $repo 'tests/runtime/run_classic_profile_browser_status_controls.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Single compiler browser runner is unavailable: $runner"}
if(-not(Test-Path -LiteralPath $runtime -PathType Container)){throw "Single compiler browser Lua runtime is unavailable: $runtime"}
$records=@()
foreach($target in @('f200','f210')){
  $output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime --target $target 2>&1)
  if($LASTEXITCODE -ne 0){throw "Single compiler browser controls failed for ${target}: $($output -join [Environment]::NewLine)"}
  $line=$output|Where-Object {$_ -match '^{.*"status": "MIR-SINGLE-COMPILER-BROWSER-CONTROLS-PASSED".*}$'}|Select-Object -Last 1
  if(-not $line){throw "Single compiler browser controls produced no success record for ${target}: $($output -join [Environment]::NewLine)"}
  $record=$line|ConvertFrom-Json
  if([int]$record.assertions -lt 5 -or [int]$record.factorio_processes -ne 0){
    throw "Browser controls did not prove the saved Classic-to-Full Library path for $target."
  }
  $records+=$record
}
[pscustomobject]@{
  status='MIR-SINGLE-COMPILER-BROWSER-CONTROLS-PASSED'
  targets=$records.target
  assertions=($records|Measure-Object -Property assertions -Sum).Sum
  source_sha256=($records|Select-Object -First 1).source_sha256
  factorio_processes=0
}
