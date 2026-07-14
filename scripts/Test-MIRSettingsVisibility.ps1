param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "scripts\validation\TargetProfiles.ps1")
$repoInfo = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
$targetProfile = Get-MIRTargetProfile -RepoRoot $repo -FactorioVersion $repoInfo.factorio_version
$isReducedLegacyLine = [bool]$targetProfile.reduced_legacy

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

function Assert-Matches {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Pattern
  )
  if ($Text -notmatch $Pattern) {
    throw "$RelativePath is missing required settings visibility pattern: $Pattern"
  }
}

function Get-RegexValues {
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Pattern,
    [int]$Group = 1
  )

  $values = @()
  foreach ($match in [regex]::Matches($Text, $Pattern)) {
    $values += $match.Groups[$Group].Value
  }
  return $values
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
$streamDescriptorText = Read-MIRText -RelativePath "prototypes/mir/domain/streams/descriptor.lua"
$catalogText = Read-MIRText -RelativePath "prototypes/mir/settings/catalog.lua"
$settingOrderText = Read-MIRText -RelativePath "prototypes/mir/settings/order.lua"
$prototypeLimitSettingsText = Read-MIRText -RelativePath "prototypes/mir/settings/prototype_limits.lua"
$registryText = Read-MIRText -RelativePath "prototypes/mir/settings/registry.lua"
$visibilityText = Read-MIRText -RelativePath "prototypes/mir/settings/visibility.lua"
$builderText = Read-MIRText -RelativePath "prototypes/mir/settings/builder.lua"
$adapterText = Read-MIRText -RelativePath "prototypes/mir/settings/stage_adapter.lua"
$profileCodecText = Read-MIRText -RelativePath "prototypes/mir/settings/profile_codec.lua"
$effectiveSettingsText = Read-MIRText -RelativePath "prototypes/mir/settings/effective.lua"
$runtimeSettingsProfileText = Read-MIRText -RelativePath "prototypes/mir/runtime/settings_profile.lua"
$testOverridesText = Read-MIRText -RelativePath "prototypes/mir/settings/test_overrides.lua"
$validationRunnerText = Read-MIRText -RelativePath "scripts/Invoke-MIRValidation.ps1"
$userSettingsDocText = Read-MIRText -RelativePath "docs/user/settings.md"
$referenceSettingsDocText = Read-MIRText -RelativePath "docs/reference/settings.md"
$settingsGovernanceDocText = Read-MIRText -RelativePath "docs/maintainer/settings-governance.md"
$defaultsText = Read-MIRText -RelativePath "prototypes/mir/settings/defaults.lua"
$productivityText = Read-MIRText -RelativePath "prototypes/streams/productivity.lua"
$directEffectsText = Read-MIRText -RelativePath "prototypes/streams/direct-effects.lua"
$fixtureText = Read-MIRText -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua"
$fixtureSettingsText = Read-MIRText -RelativePath "fixtures/assert-hidden-setting-readability/settings-final-fixes.lua"
$fixtureInfoText = Read-MIRText -RelativePath "fixtures/assert-hidden-setting-readability/info.json"
$streamKeys = @(
  Get-RegexValues -Text $productivityText -Pattern '(?m)^\s*(research_[A-Za-z0-9_]+)\s*='
  Get-RegexValues -Text $directEffectsText -Pattern '(?m)^\s*(research_[A-Za-z0-9_]+)\s*='
) | Sort-Object -Unique
$baseExtensionKeys = Get-RegexValues -Text $catalogText -Pattern '\{\s*key\s*=\s*"([^"]+)"' | Sort-Object -Unique

if ($streamKeys.Count -lt 60) {
  throw "Expected to discover at least 60 generated stream settings, found $($streamKeys.Count)."
}
if ($baseExtensionKeys.Count -lt 6) {
  throw "Expected to discover at least 6 base extension setting groups, found $($baseExtensionKeys.Count)."
}

Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "schema: 1"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "hidden_means_unavailable_not_deleted: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "do_not_force_hidden_values_by_default: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "research_air_scrubbing_clean_filter:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "research_tungsten:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "research_belts:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "profile_import_is_effective_override_not_runtime_mutation: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "settings_profiles_exclude_import_setting: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "runtime_export_writes_script_output_only: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "inactive_official_dlc_technology_settings_are_hidden_but_registered: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "experimental_automatic_family_settings_are_hidden_until_reviewed: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "technology_settings_use_three_attention_buckets: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "canonical_settings_catalog_required: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "profile_import_validates_catalog_constraints: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "settings_profiles_support_compact_export: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "settings_profile_encoding_is_deterministic: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "prototype_limit_settings_default_to_engine_default: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "prototype_limit_settings_are_startup_only_explicit_overrides: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "energy_and_pollution_caps_are_separate: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "positive_power_floor_is_default_off_opt_in: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "positive_power_floor_is_compatibility_section_setting: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "global_settings_use_visible_section_prefixes: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "rich_text_section_prefixes_are_optional_enhancement: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "fake_divider_settings_are_disallowed: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "label: Limits"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "label: Diagnostics"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "research_character_reach:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "base_extensions:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "import_setting: mir-settings-profile-import"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "string_prefix: MIRSET1"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "compact_export_command: /mir-settings-export --compact"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "validation_source: prototypes/mir/settings/catalog.lua"

Assert-Contains -RelativePath "prototypes/mir/settings/registry.lua" -Text $registryText -Needle "setting_ids_are_stable = true"
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle "function M.global_setting_prototypes()"
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle "function M.validate_value(name, value)"
Assert-Contains -RelativePath "prototypes/mir/settings/prototype_limits.lua" -Text $prototypeLimitSettingsText -Needle 'name = "mir-prototype-pollution-cap"'
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle 'name = prototype_limit_settings.positive_power_floor_setting_name'
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle 'order = setting_order.global("compatibility", 40)'
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle "function M.stream_setting_specs(key, stream)"
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle "function M.base_extension_setting_specs(key)"
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle 'require("prototypes.mir.settings.test_overrides")'
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle "return deepcopy(canonical_spec_by_name())"
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle "return deepcopy(canonical_spec_by_name()[name])"
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle "out.targets.requires_features"
Assert-Contains -RelativePath "prototypes/mir/settings/test_overrides.lua" -Text $testOverridesText -Needle "local overrides = {}"
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle "stream.descriptor.ui.sort_name"
Assert-Contains -RelativePath "prototypes/mir/settings/registry.lua" -Text $registryText -Needle 'enable = "ips-enable-%s"'
Assert-Contains -RelativePath "prototypes/mir/settings/registry.lua" -Text $registryText -Needle 'key = "mir-settings-profile-import"'
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle "function M.evaluate(spec, ctx)"
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle 'mode == "visible-if-mods-any"'
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle 'mode == "visible-if-mods-all"'
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle 'mode == "visible-if-mods-any-or-always-on-base"'
Assert-Contains -RelativePath "prototypes/mir/settings/builder.lua" -Text $builderText -Needle "setting.hidden = true"
Assert-Contains -RelativePath "prototypes/mir/settings/stage_adapter.lua" -Text $adapterText -Needle "factorio_mods.snapshot()"
Assert-Contains -RelativePath "prototypes/mir/settings/profile_codec.lua" -Text $profileCodecText -Needle 'M.prefix = "MIRSET1:"'
Assert-Contains -RelativePath "prototypes/mir/settings/profile_codec.lua" -Text $profileCodecText -Needle 'M.import_setting_name = settings_catalog.import_setting_name'
Assert-Contains -RelativePath "prototypes/mir/settings/profile_codec.lua" -Text $profileCodecText -Needle 'M.codec = "canonical-json-deflate-base64"'
Assert-Contains -RelativePath "prototypes/mir/settings/profile_codec.lua" -Text $profileCodecText -Needle "local function sorted_keys(value)"
Assert-Contains -RelativePath "prototypes/mir/settings/profile_codec.lua" -Text $profileCodecText -Needle "function M.current_profile(options)"
Assert-Contains -RelativePath "prototypes/mir/settings/effective.lua" -Text $effectiveSettingsText -Needle "function M.get(name)"
Assert-Contains -RelativePath "prototypes/mir/settings/effective.lua" -Text $effectiveSettingsText -Needle "settings_catalog.validate_value(name, imported)"
Assert-Contains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $runtimeSettingsProfileText -Needle '"mir-settings-export"'
Assert-Contains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $runtimeSettingsProfileText -Needle '"mir-settings-import-check"'
Assert-Contains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $runtimeSettingsProfileText -Needle 'Use --compact to omit defaults.'
Assert-Contains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $runtimeSettingsProfileText -Needle 'script-output/" .. filename'
Assert-Contains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $runtimeSettingsProfileText -Needle 'remote.add_interface("more-infinite-research-settings"'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle 'local settings_adapter = require("prototypes.mir.settings.stage_adapter")'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle 'local settings_catalog = require("prototypes.mir.settings.catalog")'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle 'local setting_order = require("prototypes.mir.settings.order")'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle "settings_catalog.global_setting_prototypes()"
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle 'name = "mir-settings-profile-import"'
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle "allow_blank = true"
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle "settings_adapter.visibility_for_stream(stream, settings_context)"
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle "settings_adapter.apply(setting, group and group.ui_visibility)"
Assert-Contains -RelativePath "prototypes/mir/settings/order.lua" -Text $settingOrderText -Needle 'main = "a-0"'
Assert-Contains -RelativePath "prototypes/mir/settings/order.lua" -Text $settingOrderText -Needle 'compatibility = "a-1"'
Assert-Contains -RelativePath "prototypes/mir/settings/order.lua" -Text $settingOrderText -Needle 'prototype_limits = "a-2"'
Assert-Contains -RelativePath "prototypes/mir/settings/order.lua" -Text $settingOrderText -Needle 'advanced = "a-7"'
Assert-Contains -RelativePath "prototypes/mir/settings/order.lua" -Text $settingOrderText -Needle 'diagnostics = "a-8"'
Assert-Contains -RelativePath "prototypes/mir/settings/order.lua" -Text $settingOrderText -Needle 'generated_technologies = "b"'
Assert-Contains -RelativePath "prototypes/mir/settings/order.lua" -Text $settingOrderText -Needle 'function M.global(section, index)'
Assert-Contains -RelativePath "prototypes/mir/settings/order.lua" -Text $settingOrderText -Needle 'function M.technology(bucket, name_slug, kind, key)'
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle 'order = setting_order.global("main", 10)'
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle 'order = setting_order.global("compatibility", 10)'
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle 'order = setting_order.global("advanced", 10)'
Assert-Contains -RelativePath "prototypes/mir/settings/catalog.lua" -Text $catalogText -Needle 'order = setting_order.global("diagnostics", 10)'
Assert-Contains -RelativePath "prototypes/mir/settings/prototype_limits.lua" -Text $prototypeLimitSettingsText -Needle 'order = setting_order.global("prototype_limits", 10)'
Assert-Contains -RelativePath "prototypes/mir/settings/prototype_limits.lua" -Text $prototypeLimitSettingsText -Needle 'order = setting_order.global("prototype_limits", 40)'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle 'if not group.enabled then return "000" end'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle 'if group.settings_priority == "top" then return "050" end'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle 'return "100"'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle 'return setting_order.technology(bucket, order_slug(group.sort_name), group.kind, group.key)'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle 'if rank_a ~= rank_b then return rank_a < rank_b end'
Assert-Contains -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Needle 'local sort_a = order_slug(a.sort_name)'
if (-not $isReducedLegacyLine) {
  Assert-Matches -RelativePath "prototypes/mir/settings/defaults.lua" -Text $defaultsText -Pattern '(?s)research_breeding\s*=\s*\{.*?enabled\s*=\s*true.*?settings_priority\s*=\s*"top"'
  Assert-Matches -RelativePath "prototypes/mir/settings/defaults.lua" -Text $defaultsText -Pattern '(?s)research_agricultural_growth_speed\s*=\s*\{.*?enabled\s*=\s*true.*?settings_priority\s*=\s*"top"'
  Assert-Matches -RelativePath "prototypes/mir/settings/defaults.lua" -Text $defaultsText -Pattern '(?s)research_cargo_bay_unloading_distance\s*=\s*\{.*?enabled\s*=\s*true.*?settings_priority\s*=\s*"top"'
  Assert-Matches -RelativePath "prototypes/mir/settings/defaults.lua" -Text $defaultsText -Pattern '(?s)research_cargo_landing_pad_count\s*=\s*\{.*?enabled\s*=\s*true.*?settings_priority\s*=\s*"top"'
}
Assert-Matches -RelativePath "prototypes/mir/settings/defaults.lua" -Text $defaultsText -Pattern '(?s)research_character_reach\s*=\s*\{.*?enabled\s*=\s*true.*?settings_priority\s*=\s*"top"'
if (-not $isReducedLegacyLine) {
  Assert-Matches -RelativePath "prototypes/mir/settings/defaults.lua" -Text $defaultsText -Pattern '(?s)research_spoilage_preservation\s*=\s*\{.*?enabled\s*=\s*false'
} else {
  Assert-NoPattern -RelativePath "prototypes/mir/settings/defaults.lua" -Text $defaultsText -Pattern 'research_spoilage_preservation\s*='
  Assert-NoPattern -RelativePath "prototypes/mir/settings/defaults.lua" -Text $defaultsText -Pattern 'research_agricultural_growth_speed\s*='
  Assert-NoPattern -RelativePath "prototypes/mir/settings/defaults.lua" -Text $defaultsText -Pattern 'research_cargo_(bay_unloading_distance|landing_pad_count)\s*='
}
Assert-Matches -RelativePath "prototypes/mir/settings/defaults.lua" -Text $defaultsText -Pattern '(?s)\["inserter-capacity-bonus"\]\s*=\s*\{.*?enabled\s*=\s*false.*?settings_priority\s*=\s*"top"'

Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle "ui_visibility = {"
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle 'mods_any = air_scrubbing_overlay.applies_when.mods'
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle 'mods_any = atan_ash_overlay.applies_when.mods'
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle "local function space_age_setting_visibility()"
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle 'hidden_reason = "space-age-not-active"'
if (-not $isReducedLegacyLine) {
  Assert-Contains -RelativePath "prototypes/streams/direct-effects.lua" -Text $directEffectsText -Needle "local function space_age_setting_visibility()"
  Assert-Contains -RelativePath "prototypes/streams/direct-effects.lua" -Text $directEffectsText -Needle 'hidden_reason = "space-age-not-active"'
}
Assert-Contains -RelativePath "prototypes/mir/domain/streams/descriptor.lua" -Text $streamDescriptorText -Needle 'automatic_family.creation_maturity == "experimental"'
Assert-Contains -RelativePath "prototypes/mir/domain/streams/descriptor.lua" -Text $streamDescriptorText -Needle 'hidden_reason = "experimental-family-hidden-until-reviewed"'
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle "generation_requirements = {"
if (-not $isReducedLegacyLine) {
  Assert-Contains -RelativePath "prototypes/streams/direct-effects.lua" -Text $directEffectsText -Needle "ui_visibility = space_age_setting_visibility()"
  Assert-Contains -RelativePath "prototypes/streams/direct-effects.lua" -Text $directEffectsText -Needle "generation_requirements = {"
}

Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/info.json" -Text $fixtureInfoText -Needle '"name": "mir-fixture-assert-hidden-setting-readability"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle "assert_startup_setting_readable"
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle "governed_stream_keys"
if (-not $isReducedLegacyLine) {
  Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"research_tungsten"'
  Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"research_breeding"'
  Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"research_agricultural_growth_speed"'
  Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"research_cargo_landing_pad_count"'
  Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"research_air_scrubbing_clean_filter"'
}
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"ips-enable-%s"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle "base_extension_keys"
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"worker-robots-storage"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"mir-enable-%s"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/settings-final-fixes.lua" -Text $fixtureSettingsText -Needle "assert_stream_hidden"
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/settings-final-fixes.lua" -Text $fixtureSettingsText -Needle '"research_auto_assembling_machine"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/settings-final-fixes.lua" -Text $fixtureSettingsText -Needle '"research_auto_lab"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/settings-final-fixes.lua" -Text $fixtureSettingsText -Needle 'mods["space-age"]'

foreach ($streamKey in $streamKeys) {
  Assert-Contains -RelativePath "prototypes/mir/domain/streams/descriptor.lua" -Text $streamDescriptorText -Needle "$streamKey ="
  Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle "`"$streamKey`""
}

foreach ($baseExtensionKey in $baseExtensionKeys) {
  Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle "`"$baseExtensionKey`""
}

Assert-Contains -RelativePath "docs/user/settings.md" -Text $userSettingsDocText -Needle "/mir-settings-export"
Assert-Contains -RelativePath "docs/user/settings.md" -Text $userSettingsDocText -Needle "/mir-settings-export --compact"
Assert-Contains -RelativePath "docs/user/settings.md" -Text $userSettingsDocText -Needle "mir-settings-profile-import"
Assert-Contains -RelativePath "docs/user/settings.md" -Text $userSettingsDocText -Needle "Unknown settings remain"
Assert-Contains -RelativePath "docs/user/settings.md" -Text $userSettingsDocText -Needle "Space Age-only technology settings are hidden"
Assert-Contains -RelativePath "docs/user/settings.md" -Text $userSettingsDocText -Needle "Experimental automatic-family tuning settings are hidden"
Assert-Contains -RelativePath "docs/reference/settings.md" -Text $referenceSettingsDocText -Needle "MIRSET1:<encoded-json>"
Assert-Contains -RelativePath "docs/reference/settings.md" -Text $referenceSettingsDocText -Needle "Unknown setting IDs, wrong value types, invalid enum values, and out-of-range"
Assert-Contains -RelativePath "docs/maintainer/settings-governance.md" -Text $settingsGovernanceDocText -Needle "Portable Profiles"
Assert-Contains -RelativePath "docs/maintainer/settings-governance.md" -Text $settingsGovernanceDocText -Needle "runtime commands may export or validate profiles"

Assert-NoPattern -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Pattern "\bdata\.raw\b|data:extend|settings\.startup"
Assert-NoPattern -RelativePath "prototypes/mir/settings/builder.lua" -Text $builderText -Pattern "forced_value"
Assert-NoPattern -RelativePath "prototypes/mir/settings/stage_builder.lua" -Text $stageBuilderText -Pattern "forced_value"
Assert-NoPattern -RelativePath "scripts/Invoke-MIRValidation.ps1" -Text $validationRunnerText -Pattern '\$copied(Settings|Defaults|Diagnostics)\s*=.*-replace'
Assert-NoPattern -RelativePath "scripts/Invoke-MIRValidation.ps1" -Text $validationRunnerText -Pattern 'data:extend\\\(settings_data\\\).*setting.default_value'
Assert-NoPattern -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Pattern 'official-stream-settings-visible'
Assert-NoPattern -RelativePath "prototypes/streams/direct-effects.lua" -Text $directEffectsText -Pattern 'official-stream-settings-visible'

Assert-NoPatternInTree `
  -RelativeRoot "prototypes" `
  -Pattern "settings_required_mods" `
  -Message "Stream setting visibility must use ui_visibility, not settings_required_mods."

Write-Host "[ok] MIR settings visibility lint passed."
