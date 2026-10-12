[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$PythonExe='python',
  [string]$LuaRuntimeDir='build/tmp/mir421-lua-runtime'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$runner = Join-Path $repo 'tests/compiler/run_contextual_boolean_acquisition_memo_controls.py'
$source = Join-Path $repo 'source/prototypes/mir/capabilities/science_integration/pack_production_reachability.lua'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf) -or -not (Test-Path -LiteralPath $source -PathType Leaf)) {
  throw 'Contextual Boolean acquisition memo control inputs are unavailable.'
}
$runtime = if ([IO.Path]::IsPathFullyQualified($LuaRuntimeDir)) { $LuaRuntimeDir } else { Join-Path $repo $LuaRuntimeDir }
if (-not (Test-Path -LiteralPath $runtime -PathType Container)) {
  throw "Contextual Boolean acquisition memo Lua runtime is unavailable: $runtime"
}

$output = @(& $PythonExe $runner --repo-root $repo --lua-runtime-dir $runtime 2>&1)
if ($LASTEXITCODE -ne 0) {
  throw "Contextual Boolean acquisition memo controls failed: $($output -join [Environment]::NewLine)"
}
$recordLine = $output | Where-Object { $_ -match '^\{.*"status": "MIR-CONTEXTUAL-BOOLEAN-ACQUISITION-MEMO-CONTROLS-PASSED".*\}$' } | Select-Object -Last 1
if (-not $recordLine) {
  throw "Contextual Boolean acquisition memo controls produced no success record: $($output -join [Environment]::NewLine)"
}
$record = $recordLine | ConvertFrom-Json
if ([int]$record.assertions -lt 21 -or [int]$record.acquisition_calls -lt 20 -or [int]$record.factorio_processes -ne 0) {
  throw 'Contextual Boolean acquisition memo controls did not retain their required positive-only/cold-fallback coverage.'
}
[pscustomobject]@{
  status=[string]$record.status
  assertions=[int]$record.assertions
  acquisition_calls=[int]$record.acquisition_calls
  source_sha256=[string]$record.source_sha256
  fixture_sha256=[string]$record.fixture_sha256
  runtime=[string]$record.runtime
  factorio_processes=[int]$record.factorio_processes
}
