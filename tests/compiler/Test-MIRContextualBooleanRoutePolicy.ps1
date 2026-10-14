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
$runner=Join-Path $repo 'tests/compiler/run_contextual_boolean_route_policy_controls.py'
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
if(-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw "Contextual Boolean route-policy runner is unavailable: $runner"}
if(-not(Test-Path -LiteralPath $runtime -PathType Container)){throw "Contextual Boolean route-policy Lua runtime is unavailable: $runtime"}

$records=@()
foreach($target in @('f200','f210')){
  $output=@(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime --target $target 2>&1)
  if($LASTEXITCODE -ne 0){throw "Contextual Boolean route-policy controls failed for ${target}: $($output -join [Environment]::NewLine)"}
  $recordLine=$output|Where-Object {$_ -match '^{.*"status": "MIR-CONTEXTUAL-BOOLEAN-ROUTE-POLICY-CONTROLS-PASSED".*}$'}|Select-Object -Last 1
  if(-not $recordLine){throw "Contextual Boolean route-policy controls produced no success record for ${target}: $($output -join [Environment]::NewLine)"}
  $record=$recordLine|ConvertFrom-Json
  if([string]$record.scope -cne 'retired-discovery-characterization-not-current-package-certification'){throw 'Retired discovery controls must remain package-excluded characterizations.'}
  if([int]$record.assertions -lt 11 -or -not [bool]$record.cold_available -or -not [bool]$record.warm_available -or [int]$record.boolean_hits -lt 1 -or [int]$record.factorio_processes -ne 0){
    throw "Contextual Boolean route-policy controls did not preserve complete availability or selected-route equivalence for $target."
  }
  $records+=$record
}
[pscustomobject]@{
  status='MIR-CONTEXTUAL-BOOLEAN-ROUTE-POLICY-CONTROLS-PASSED'
  scope=[string]$records[0].scope
  targets=$records.target
  assertions=($records|Measure-Object -Property assertions -Sum).Sum
  source_sha256=($records|Select-Object -First 1).source_sha256
  factorio_processes=0
}
