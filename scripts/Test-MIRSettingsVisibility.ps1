param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Read-MIRText {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path = Join-Path $repo $RelativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required settings visibility file: $RelativePath"
  }
  return Get-Content -Raw -LiteralPath $path
}

function Assert-Contains {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )
  if (-not $Text.Contains($Needle)) {
    throw "$RelativePath is missing required settings visibility snippet: $Needle"
  }
}

function Assert-NoPattern {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Pattern
  )
  if ($Text -match $Pattern) {
    throw "$RelativePath contains forbidden settings visibility pattern: $Pattern"
  }
}

function Assert-NoPatternInTree {
  param(
    [Parameter(Mandatory)][string]$RelativeRoot,
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][string]$Message
  )

  $root = Join-Path $repo $RelativeRoot
  if (-not (Test-Path -LiteralPath $root)) { return }

  $matches = @(
    Get-ChildItem -LiteralPath $root -Recurse -File |
      Where-Object { $_.Extension -in @(".lua", ".yml", ".md", ".ps1") } |
      Select-String -Pattern $Pattern
  )

  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw $Message
  }
}

$settingsManifestText = Read-MIRText -RelativePath ".mir/settings.yml"
$stageBuilderText = Read-MIRText -RelativePath "prototypes/mir/settings/stage_builder.lua"
$registryText = Read-MIRText -RelativePath "prototypes/mir/settings/registry.lua"
$visibilityText = Read-MIRText -RelativePath "prototypes/mir/settings/visibility.lua"
$builderText = Read-MIRText -RelativePath "prototypes/mir/settings/builder.lua"
$adapterText = Read-MIRText -RelativePath "prototypes/mir/settings/stage_adapter.lua"
$profileCodecText = Read-MIRText -RelativePath "prototypes/mir/settings/profile_codec.lua"
$effectiveSettingsText = Read-MIRText -RelativePath "prototypes/mir/settings/effective.lua"
$runtimeSettingsProfileText = Read-MIRText -RelativePath "prototypes/mir/runtime/settings_profile.lua"
$userSettingsDocText = Read-MIRText -RelativePath "docs/user/settings.md"
$referenceSettingsDocText = Read-MIRText -RelativePath "docs/reference/settings.md"
$settingsGovernanceDocText = Read-MIRText -RelativePath "docs/maintainer/settings-governance.md"
$productivityText = Read-MIRText -RelativePath "prototypes/streams/productivity.lua"
$directEffectsText = Read-MIRText -RelativePath "prototypes/streams/direct-effects.lua"
$fixtureText = Read-MIRText -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua"
$fixtureInfoText = Read-MIRText -RelativePath "fixtures/assert-hidden-setting-readability/info.json"

Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "schema: 1"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "hidden_means_unavailable_not_deleted: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "do_not_force_hidden_values_by_default: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "research_air_scrubbing_clean_filter:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "research_tungsten:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "research_belts:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "profile_import_is_effective_override_not_runtime_mutation: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "settings_profiles_exclude_import_setting: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "runtime_export_writes_script_output_only: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "official_and_mir_owned_technology_settings_stay_visible: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "technology_settings_use_three_attention_buckets: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "prototype_limit_settings_default_to_engine_default: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "prototype_limit_settings_are_startup_only_explicit_overrides: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "research_character_reach:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "base_extensions:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "import_setting: mir-settings-profile-import"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "string_prefix: MIRSET1"

Assert-Contains -RelativePath "prototypes/mir/settings/registry.lua" -Text $registryText -Needle "setting_ids_are_stable = true"
Assert-Contains -RelativePath "prototypes/mir/settings/registry.lua" -Text $registryText -Needle 'enable = "ips-enable-%s"'
Assert-Contains -RelativePath "prototypes/mir/settings/registry.lua" -Text $registryText -Needle 'key = "mir-settings-profile-import"'
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle "function M.evaluate(spec, ctx)"
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle 'mode == "visible-if-mods-any"'
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle 'mode == "visible-if-mods-all"'
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle 'mode == "visible-if-mods-any-or-always-on-base"'
Assert-Contains -RelativePath "prototypes/mir/settings/builder.lua" -Text $builderText -Needle "setting.hidden = true"
Assert-Contains -RelativePath "prototypes/mir/settings/stage_adapter.lua" -Text $adapterText -Needle "factorio_mods.snapshot()"
Assert-Contains -RelativePath "prototypes/mir/settings/profile_codec.lua" -Text $profileCodecText -Needle 'M.prefix = "MIRSET1:"'
Assert-Contains -RelativePath "prototypes/mir/settings/profile_codec.lua" -Text $profileCodecText -Needle 'M.import_setting_name = "mir-settings-profile-import"'
Assert-Contains -RelativePath "prototypes/mir/settings/profile_codec.lua" -Text $profileCodecText -Needle "function M.current_profile(options)"
Assert-Contains -RelativePath "prototypes/mir/settings/effective.lua" -Text $effectiveSettingsText -Needle "function M.get(name)"
Assert-Contains -RelativePath "prototypes/mir/settings/effective.lua" -Text $effectiveSettingsText -Needle "type_matches(imported, raw_setting(name))"
Assert-Contains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $runtimeSettingsProfileText -Needle '"mir-settings-export"'
Assert-Contains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $runtimeSettingsProfileText -Needle '"mir-settings-import-check"'
Assert-Contains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $runtimeSettingsProfileText -Needle 'script-output/" .. filename'
Assert-Contains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $runtimeSettingsProfileText -Needle 'remote.add_interface("more-infinite-research-settings"'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle 'local settings_adapter = require("prototypes.mir.settings.stage_adapter")'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle 'name = "mir-settings-profile-import"'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle "allow_blank = true"
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle "settings_adapter.visibility_for_stream(stream, settings_context)"
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle "settings_adapter.apply(setting, group and group.ui_visibility)"

Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle "ui_visibility = {"
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle 'mods_any = air_scrubbing_overlay.applies_when.mods'
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle 'mods_any = atan_ash_overlay.applies_when.mods'
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle 'reason = "official-stream-settings-visible"'
Assert-Contains -RelativePath "prototypes/streams/direct-effects.lua" -Text $directEffectsText -Needle 'reason = "official-stream-settings-visible"'
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle "generation_requirements = {"
Assert-Contains -RelativePath "prototypes/streams/direct-effects.lua" -Text $directEffectsText -Needle "ui_visibility = {"
Assert-Contains -RelativePath "prototypes/streams/direct-effects.lua" -Text $directEffectsText -Needle "generation_requirements = {"

Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/info.json" -Text $fixtureInfoText -Needle '"name": "mir-fixture-assert-hidden-setting-readability"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle "assert_startup_setting_readable"
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle "governed_stream_keys"
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"research_tungsten"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"research_breeding"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"research_agricultural_growth_speed"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"research_cargo_landing_pad_count"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"research_air_scrubbing_clean_filter"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"ips-enable-%s"'

Assert-Contains -RelativePath "docs/user/settings.md" -Text $userSettingsDocText -Needle "/mir-settings-export"
Assert-Contains -RelativePath "docs/user/settings.md" -Text $userSettingsDocText -Needle "mir-settings-profile-import"
Assert-Contains -RelativePath "docs/user/settings.md" -Text $userSettingsDocText -Needle "Unknown settings remain"
Assert-Contains -RelativePath "docs/reference/settings.md" -Text $referenceSettingsDocText -Needle "MIRSET1:<encoded-json>"
Assert-Contains -RelativePath "docs/reference/settings.md" -Text $referenceSettingsDocText -Needle "Unknown setting IDs and mismatched value types are ignored"
Assert-Contains -RelativePath "docs/maintainer/settings-governance.md" -Text $settingsGovernanceDocText -Needle "Portable Profiles"
Assert-Contains -RelativePath "docs/maintainer/settings-governance.md" -Text $settingsGovernanceDocText -Needle "runtime commands may export or validate profiles"

Assert-NoPattern -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Pattern "\bdata\.raw\b|data:extend|settings\.startup"
Assert-NoPattern -RelativePath "prototypes/mir/settings/builder.lua" -Text $builderText -Pattern "forced_value"
Assert-NoPattern -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Pattern "forced_value"
Assert-NoPattern -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Pattern 'mods_any = \{"space-age"\}'
Assert-NoPattern -RelativePath "prototypes/streams/direct-effects.lua" -Text $directEffectsText -Pattern 'mods_any = \{"space-age"\}'

Assert-NoPatternInTree `
  -RelativeRoot "prototypes" `
  -Pattern "settings_required_mods" `
  -Message "Stream setting visibility must use ui_visibility, not settings_required_mods."

Write-Host "[ok] MIR settings visibility lint passed."
