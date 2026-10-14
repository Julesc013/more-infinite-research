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
$runtime=if([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)){$LuaRuntimeDir}else{Join-Path $repo $LuaRuntimeDir}
$result=@(& $PythonExe (Join-Path $repo 'tests/compiler/run_approved_pack_bindings_controls.py') --repo-root $repo --lua-runtime-dir $runtime 2>&1)
if($LASTEXITCODE -ne 0){throw "Approved pack binding controls failed: $($result -join [Environment]::NewLine)"}
$record=$result[-1] | ConvertFrom-Json
if($record.status -cne 'MIR-APPROVED-PACK-BINDINGS-PASSED' -or $record.assertions -lt 198 -or $record.factorio_processes -ne 0){throw 'Incomplete approved pack binding controls.'}
if($record.emission_control.assertions -lt 7 -or $record.emission_control.catalogue_rows -lt 100 -or $record.emission_control.stubbed_module_boundaries.Count -ne 0){throw 'Incomplete common-emitter preservation controls.'}
$record | ConvertTo-Json -Depth 8
