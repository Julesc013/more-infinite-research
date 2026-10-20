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
if($record.status -cne 'MIR-APPROVED-PACK-BINDINGS-PASSED' -or $record.assertions -lt 220 -or $record.factorio_processes -ne 0){throw 'Incomplete approved pack binding controls.'}
if($record.emission_control.assertions -lt 7 -or $record.emission_control.catalogue_rows -lt 100 -or $record.emission_control.stubbed_module_boundaries.Count -ne 0){throw 'Incomplete common-emitter preservation controls.'}
if($record.clockless_emission_control.assertions -ne ($record.emission_control.assertions + 2) -or $record.clockless_emission_control.catalogue_rows -ne $record.emission_control.catalogue_rows -or $record.clockless_emission_control.operations -ne $record.emission_control.operations -or $record.clockless_emission_control.stubbed_module_boundaries.Count -ne 0){throw 'Incomplete clockless common-emitter controls.'}
$exports=$record.command_export_control
if($null -eq $exports -or [string]::IsNullOrWhiteSpace([string]$exports.run_all_default.input_fingerprint) -or
    [string]::IsNullOrWhiteSpace([string]$exports.run_all_default.snapshot_fingerprint) -or
    [string]::IsNullOrWhiteSpace([string]$exports.manual_new_context.input_fingerprint) -or
    [string]::IsNullOrWhiteSpace([string]$exports.manual_new_context.snapshot_fingerprint) -or
    [string]::IsNullOrWhiteSpace([string]$exports.run_all_active_only.input_fingerprint)){
  throw 'Incomplete command export-boundary controls.'
}
$record | ConvertTo-Json -Depth 8
