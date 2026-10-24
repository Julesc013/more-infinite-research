param(
  [string]$LuaRuntimeDir,
  [switch]$Plan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path

$controls = @(
  [ordered]@{path='tests/mir5/test_generator.py';lua=$true},
  [ordered]@{path='tests/mir5/test_historical_direct.py';lua=$true},
  [ordered]@{path='tests/mir5/test_historical_continuations.py';lua=$true},
  [ordered]@{path='tests/mir5/test_historical_native_runner.py';lua=$true},
  [ordered]@{path='tests/mir5/test_historical_transition_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_modern_targets.py';lua=$true},
  [ordered]@{path='tests/mir5/test_k2_base_catalogue.py';lua=$true},
  [ordered]@{path='tests/mir5/test_k2_base_native_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_bob_angel_materials.py';lua=$true},
  [ordered]@{path='tests/mir5/test_bob_angel_catalogue.py';lua=$true},
  [ordered]@{path='tests/mir5/test_bob_tech_materials.py';lua=$true},
  [ordered]@{path='tests/mir5/test_bob_core_materials.py';lua=$true},
  [ordered]@{path='tests/mir5/test_bob_core_gameplay_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_override_interactions_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_armor_py_catalogue.py';lua=$true},
  [ordered]@{path='tests/mir5/test_native_modded_continuations.py';lua=$true},
  [ordered]@{path='tests/mir5/test_bob_angel_native_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_bob_angel_prototype_caps.py';lua=$true},
  [ordered]@{path='tests/mir5/test_atan_productivity.py';lua=$true},
  [ordered]@{path='tests/mir5/test_atan_gameplay_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_full_catalogue_upgrade_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_fixed_provider_removal_control_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_automatic_families.py';lua=$true},
  [ordered]@{path='tests/mir5/test_competing_productivity.py';lua=$true},
  [ordered]@{path='tests/mir5/test_native_credit_definitions.py';lua=$true},
  [ordered]@{path='tests/mir5/test_native_credits.py';lua=$true},
  [ordered]@{path='tests/mir5/test_legacy_preference_transition_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_competing_epr_native_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_competing_fixed_reference.py';lua=$true},
  [ordered]@{path='tests/mir5/test_competing_fixed_native_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_competing_dynamic_native_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_science.py';lua=$true},
  [ordered]@{path='tests/mir5/test_cryogenic_native_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_cryogenic_gameplay_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_material_catalogue.py';lua=$true},
  [ordered]@{path='tests/mir5/test_material_native_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_product_targets.py';lua=$true},
  [ordered]@{path='tests/mir5/test_product_target_extension.py';lua=$true},
  [ordered]@{path='tests/mir5/test_diagnostics.py';lua=$true},
  [ordered]@{path='tests/mir5/test_target_adapters.py';lua=$true},
  [ordered]@{path='tests/mir5/test_caps.py';lua=$true},
  [ordered]@{path='tests/mir5/test_legacy_caps.py';lua=$true},
  [ordered]@{path='tests/mir5/test_legacy_caps_lifecycle.py';lua=$true},
  [ordered]@{path='tests/mir5/test_f200_legacy_cap_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_f200_legacy_worker_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_k2_imersite_migration.py';lua=$true},
  [ordered]@{path='tests/mir5/test_k2_imersite_transition_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_api.py';lua=$true},
  [ordered]@{path='tests/mir5/test_runtime_api.py';lua=$true},
  [ordered]@{path='tests/mir5/test_sdk.py';lua=$true},
  [ordered]@{path='tests/mir5/test_fixture_controls.py';lua=$true},
  [ordered]@{path='tests/mir5/test_foreign_research_preservation.py';lua=$true},
  [ordered]@{path='tests/mir5/test_capture_controls.py';lua=$true},
  [ordered]@{path='tests/mir5/test_lifecycle.py';lua=$true},
  [ordered]@{path='tests/mir5/test_native_owners.py';lua=$true},
  [ordered]@{path='tests/mir5/test_module_permissions_override.py';lua=$true},
  [ordered]@{path='tests/mir5/test_prototype_limits.py';lua=$true},
  [ordered]@{path='tests/mir5/test_recipe_schema_repairs.py';lua=$true},
  [ordered]@{path='tests/mir5/test_module_permissions_activation.py';lua=$true},
  [ordered]@{path='tests/mir5/test_bootstrap.py';lua=$true},
  [ordered]@{path='tests/mir5/test_library.py';lua=$true},
  [ordered]@{path='tests/mir5/test_library_multiplayer_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_scripted_effects_multiplayer_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_scripted_effects_toggle_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_library_model.py';lua=$true},
  [ordered]@{path='tests/mir5/test_library_translations.py';lua=$true},
  [ordered]@{path='tests/mir5/test_passive_repair.py';lua=$true},
  [ordered]@{path='tests/mir5/test_repair_stress_fixture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_agriculture.py';lua=$true},
  [ordered]@{path='tests/mir5/test_spoilage.py';lua=$true},
  [ordered]@{path='tests/mir5/test_scripted_effects_lifecycle.py';lua=$true},
  [ordered]@{path='tests/mir5/test_settings_profile.py';lua=$true},
  [ordered]@{path='tests/mir5/test_settings_commands.py';lua=$true},
  [ordered]@{path='tests/mir5/test_properties.py';lua=$true},
  [ordered]@{path='tests/mir5/test_replay.py';lua=$true},
  [ordered]@{path='tests/mir5/test_package.py';lua=$false},
  [ordered]@{path='tests/mir5/test_release.py';lua=$false},
  [ordered]@{path='tests/mir5/test_compose_replay.py';lua=$false},
  [ordered]@{path='tests/mir5/test_compare_captures.py';lua=$false},
  [ordered]@{path='tests/mir5/test_recover_modern_catalogue.py';lua=$false},
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
