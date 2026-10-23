param(
  [string]$LuaRuntimeDir,
  [switch]$Plan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path

$controls = @(
  [ordered]@{path='tests/mir5/test_generator.py';lua=$true},
  [ordered]@{path='tests/mir5/test_caps.py';lua=$true},
  [ordered]@{path='tests/mir5/test_api.py';lua=$true},
  [ordered]@{path='tests/mir5/test_runtime_api.py';lua=$true},
  [ordered]@{path='tests/mir5/test_fixture_controls.py';lua=$true},
  [ordered]@{path='tests/mir5/test_lifecycle.py';lua=$true},
  [ordered]@{path='tests/mir5/test_native_owners.py';lua=$true},
  [ordered]@{path='tests/mir5/test_bootstrap.py';lua=$true},
  [ordered]@{path='tests/mir5/test_library.py';lua=$true},
  [ordered]@{path='tests/mir5/test_library_model.py';lua=$true},
  [ordered]@{path='tests/mir5/test_properties.py';lua=$true},
  [ordered]@{path='tests/mir5/test_replay.py';lua=$true},
  [ordered]@{path='tests/mir5/test_package.py';lua=$false},
  [ordered]@{path='tests/mir5/test_compose_replay.py';lua=$false},
  [ordered]@{path='tests/mir5/test_compare_captures.py';lua=$false},
  [ordered]@{path='tests/mir5/test_menu_comparison.py';lua=$false},
  [ordered]@{path='tests/mir5/test_pack.py';lua=$false},
  [ordered]@{path='tests/mir5/test_host_controls.py';lua=$false},
  [ordered]@{path='tools/mir5/check_pack.py';lua=$false}
)

if ($Plan) {
  [pscustomobject][ordered]@{schema=1;kind='MIR5HostControlsPlanV1';controls=$controls;native_execution=$false;release_qualification=$false}
  return
}
if ([string]::IsNullOrWhiteSpace($LuaRuntimeDir)) { $LuaRuntimeDir = [string]$env:MIR5_LUA_RUNTIME }
if ([string]::IsNullOrWhiteSpace($LuaRuntimeDir)) { throw '[mir5-host-controls-lua-runtime-required]' }
$runtime = (Resolve-Path -LiteralPath $LuaRuntimeDir -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath (Join-Path $runtime 'lupa') -PathType Container)) { throw '[mir5-host-controls-lua-runtime-invalid]' }
$python = (Get-Command python -ErrorAction Stop).Source

foreach ($control in $controls) {
  $controlPath = Join-Path $repo ([string]$control.path)
  if (-not (Test-Path -LiteralPath $controlPath -PathType Leaf)) { throw "[mir5-host-controls-missing] $($control.path)" }
  $arguments = @('-B', $controlPath)
  if ([bool]$control.lua) { $arguments += @('--lua-runtime-dir', $runtime) }
  & $python @arguments
  if ($LASTEXITCODE -ne 0) { throw "[mir5-host-controls-failed] $($control.path)" }
}

[pscustomobject][ordered]@{status='passed';controls=$controls.Count;native_execution=$false;release_qualification=$false}
