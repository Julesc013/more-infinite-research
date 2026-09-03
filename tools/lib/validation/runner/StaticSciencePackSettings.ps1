Invoke-RepoCheck "science-pack progression settings are wired" {
  $settingsText = Get-MIRSettingsSourceText
  $baseContinuationsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\planner\base_continuations.lua")
  $settingsResolverText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\resolver.lua")
  $settingsRegistryText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\registry.lua")
  $settingsVisibilityText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\visibility.lua")
  $settingsBuilderText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\builder.lua")
  $settingsStageAdapterText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\stage_adapter.lua")
  $runtimeSettingsResolverText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\runtime\settings_resolver.lua")
  $spoilageText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\runtime\effects\spoilage_preservation.lua")
  $agriculturalGrowthText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\runtime\effects\agricultural_growth_speed.lua")
  $scienceText = Get-MIRCombinedSourceText -RelativePaths @(
    "prototypes/mir/capabilities/science_integration/science_packs.lua",
    "prototypes/mir/capabilities/science_integration/pack_registry.lua",
    "prototypes/mir/capabilities/science_integration/lab_compatibility.lua",
    "prototypes/mir/capabilities/science_integration/recipe_unlock_facts.lua",
    "prototypes/mir/capabilities/science_integration/technology_researchability.lua",
    "prototypes/mir/capabilities/science_integration/pack_production_reachability.lua",
    "prototypes/mir/capabilities/science_integration/science_selection_policy.lua"
  )
  $scienceSelectorText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\capabilities\science_integration\science_selector.lua")
  $directEffectsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\streams\direct-effects.lua")
  $productivityText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\streams\productivity.lua")
  $recipeMatchingText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\capabilities\recipe_productivity\recipe_matching.lua")
  $prototypeLookupText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\platform\factorio\prototype_lookup.lua")
  $technologyIconsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\presentation\icon_builder.lua")
  $plannerCostsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\planner\costs.lua")
  $plannerPrerequisitesText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\planner\prerequisites.lua")
  $plannerRequirementsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\planner\requirements.lua")
  $recipeUnlockIndexText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\index\recipe_unlocks.lua")
  $productivityStreamsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\streams\productivity.lua")
  $dataFinalFixesText = Get-MIRDataFinalFixesSourceText
  $pipelineExtentText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\pipeline\extent.lua")
  $pipelineExtentSettingsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\pipeline_extent.lua")
  $diagnosticsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\report\diagnostics_sink.lua")
  $weaponSpeedText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\policy\weapon_speed.lua")
  $nativeEffectCoverageText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\policy\native_effect_coverage.lua")
  $generatedRegistryText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\domain\facts\generated_technology_registry.lua")
  $weaponSpeedFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-weapon-speed-safety\data-final-fixes.lua")
  $generationIntegrityFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-generation-integrity\data-final-fixes.lua")
  $generatedPrerequisiteFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-generated-prerequisite-safety\data-final-fixes.lua")
  $generatedPrerequisiteSetupText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-generated-prerequisite-safety\data-updates.lua")
  $generatedPrerequisiteRuntimeText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-generated-prerequisite-safety\control.lua")
  $lateRecipeRemovalFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\rigor-late-recipe-removal\data-final-fixes.lua")
  $lateRecipeRemovalDataText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\rigor-late-recipe-removal\data.lua")
  $spaceExplorationRemovalFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\space-exploration-recipe-removal\data-final-fixes.lua")
  $finalRecipeEffectFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-final-recipe-effect-integrity\data-final-fixes.lua")
  $fluidProductivityFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-fluid-productivity\data-final-fixes.lua")
  $pipelineExtentFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-pipeline-extent\data-final-fixes.lua")
  $betterBotBatteryFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-better-bot-battery-skip\data-final-fixes.lua")
  $airScrubbingFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua")
  $atanAshFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\atan-ash\data.lua")
  $atanAshAssertText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-atan-ash-separation\data-final-fixes.lua")
  $aaiLoaderFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-aai-loader-belt-productivity\data-final-fixes.lua")
  $bigMiningDrillFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-big-mining-drill-productivity\data-final-fixes.lua")
  $semanticFamilyFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-semantic-family-attach\data-final-fixes.lua")
  $atanNuclearScienceFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-atan-nuclear-science-productivity\data-final-fixes.lua")
  $capabilityNegativeFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\capability-negative-cases\data.lua")
  $capabilityNegativeAssertText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-capability-negative-cases\data-final-fixes.lua")
  $recipeRiskFactsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\index\recipe_risk_facts.lua")
  $defaultsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\defaults.lua")
  $localeText = Get-Content -Raw -LiteralPath (Join-Path $repo "locale\en\more-infinite-research.cfg")

  $requiredSnippets = @(
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'name = "ips-require-space-gate"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'default_value = false' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'name = "mir-science-pack-ingredient-policy"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'allowed_values = {"configured", "space", "space-and-promethium", "space-age-progression", "official-progression", "mod-progression", "all-official", "all"}' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'allowed_values = {"reduce", "skip", "engine-default"}' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'name = "mir-use-installed-space-age-icons"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local setting_order = require("prototypes.mir.settings.order")' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'order = setting_order.global("compatibility", 20)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local pipeline_extent_settings = require("prototypes.mir.settings.pipeline_extent")' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local settings_adapter = require("prototypes.mir.settings.stage_adapter")' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'name = "mir-pipeline-extent-multiplier"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'type = "string-setting"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'allowed_values = pipeline_extent_settings.allowed_values' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'order = setting_order.global("compatibility", 30)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local function append_note(description, note)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local function add_technology_setting(group, setting)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local settings_sort_names = {' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_agricultural_growth_speed = "Agricultural growth speed"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_character_reach = "Character reach bonus"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_oil_processing_productivity = "Oil processing productivity"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_spoilage_preservation = "Spoilage preservation"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_thruster_fuel_productivity = "Thruster fuel productivity"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local function group_order_prefix(group)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local technology_setting_groups = {}' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'kind = "stream"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'kind = "base"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'settings_adapter.visibility_for_stream(stream, settings_context)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'settings_adapter.apply(setting, group and group.ui_visibility)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local function group_attention_rank(group)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local risk_rank = technology_risk.settings_rank(group.technology_risk)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'if risk_rank then return risk_rank end' },
    @{ File = "prototypes\mir\settings\defaults.lua"; Text = $defaultsText; Snippet = 'settings_priority = "top"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'order = setting_order.global("diagnostics", 10)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'settings_catalog.stream_setting_specs(key, stream)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'decorate_stream_setting(spec, tech_locale, order_prefix, group.technology_risk)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'settings_catalog.base_extension_setting_specs(spec.key)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'ips-effect-per-level' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local locale_key = defaults_spec.locale_key or defaults_spec.chain_key or spec.locale_key or spec.key' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'out.localised_name = {"mod-setting-name.mir-max-level", tech_locale}' },
    @{ File = "prototypes\mir\settings\resolver.lua"; Text = $settingsResolverText; Snippet = 'function R.stream_enabled(key, spec)' },
    @{ File = "prototypes\mir\settings\resolver.lua"; Text = $settingsResolverText; Snippet = 'function R.base_enabled(key, spec)' },
    @{ File = "prototypes\mir\settings\registry.lua"; Text = $settingsRegistryText; Snippet = 'hidden_means_unavailable_not_deleted = true' },
    @{ File = "prototypes\mir\settings\registry.lua"; Text = $settingsRegistryText; Snippet = 'do_not_force_hidden_values_by_default = true' },
    @{ File = "prototypes\mir\settings\visibility.lua"; Text = $settingsVisibilityText; Snippet = 'function M.evaluate(spec, ctx)' },
    @{ File = "prototypes\mir\settings\visibility.lua"; Text = $settingsVisibilityText; Snippet = 'mode == "visible-if-mods-any"' },
    @{ File = "prototypes\mir\settings\visibility.lua"; Text = $settingsVisibilityText; Snippet = 'mode == "visible-if-mods-all"' },
    @{ File = "prototypes\mir\settings\builder.lua"; Text = $settingsBuilderText; Snippet = 'function M.apply_visibility(setting, result)' },
    @{ File = "prototypes\mir\settings\builder.lua"; Text = $settingsBuilderText; Snippet = 'setting.hidden = true' },
    @{ File = "prototypes\mir\settings\stage_adapter.lua"; Text = $settingsStageAdapterText; Snippet = 'factorio_mods.snapshot()' },
    @{ File = "prototypes\mir\settings\resolver.lua"; Text = $settingsResolverText; Snippet = 'startup_setting("ips-enable-" .. key)' },
    @{ File = "prototypes\mir\settings\resolver.lua"; Text = $settingsResolverText; Snippet = 'startup_setting("mir-enable-" .. key)' },
    @{ File = "prototypes\mir\runtime\settings_resolver.lua"; Text = $runtimeSettingsResolverText; Snippet = 'function R.stream_enabled(key)' },
    @{ File = "prototypes\mir\runtime\settings_resolver.lua"; Text = $runtimeSettingsResolverText; Snippet = 'startup_setting("ips-enable-" .. key)' },
    @{ File = "prototypes\mir\runtime\effects\spoilage_preservation.lua"; Text = $spoilageText; Snippet = 'settings_resolver.stream_enabled(M.stream_key)' },
    @{ File = "prototypes\mir\runtime\effects\spoilage_preservation.lua"; Text = $spoilageText; Snippet = 'spoilage preservation skipped: disabled' },
    @{ File = "prototypes\mir\runtime\effects\agricultural_growth_speed.lua"; Text = $agriculturalGrowthText; Snippet = 'settings_resolver.stream_enabled(M.stream_key)' },
    @{ File = "prototypes\mir\runtime\effects\agricultural_growth_speed.lua"; Text = $agriculturalGrowthText; Snippet = 'agricultural growth speed force state refreshed enabled=' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_selector.lua"; Text = $scienceSelectorText; Snippet = 'apply_science_pack_ingredient_policy' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_selector.lua"; Text = $scienceSelectorText; Snippet = 'if policy == "configured" then' },
    @{ File = "prototypes\mir\capabilities\science_integration"; Text = $scienceText; Snippet = 'if policy() == "engine-default" then' },
    @{ File = "prototypes\mir\planner\costs.lua"; Text = $plannerCostsText; Snippet = 'settings_resolver.stream_enabled(key, spec)' },
    @{ File = "prototypes\mir\planner\base_continuations.lua"; Text = $baseContinuationsText; Snippet = 'settings_resolver.base_enabled(key, spec)' },
    @{ File = "prototypes\mir\planner\prerequisites.lua"; Text = $plannerPrerequisitesText; Snippet = 'append_end_game_gate_prerequisite' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_packs.lua"; Text = $scienceText; Snippet = 'pack_list_official' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_packs.lua"; Text = $scienceText; Snippet = 'is_official_science_pack' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_packs.lua"; Text = $scienceText; Snippet = 'space_age_progression_packs_for' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_packs.lua"; Text = $scienceText; Snippet = 'official_progression_packs_for' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_packs.lua"; Text = $scienceText; Snippet = 'mod_progression_packs_for' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_packs.lua"; Text = $scienceText; Snippet = 'desired == "all-official"' },
    @{ File = "prototypes\mir\planner\base_continuations.lua"; Text = $baseContinuationsText; Snippet = 'if data_raw.technology(new_name) then' },
    @{ File = "prototypes\mir\planner\base_continuations.lua"; Text = $baseContinuationsText; Snippet = '"target_exists"' },
    @{ File = "prototypes\mir\planner\base_continuations.lua"; Text = $baseContinuationsText; Snippet = 'apply_science_pack_ingredient_policy' },
    @{ File = "prototypes\mir\planner\base_continuations.lua"; Text = $baseContinuationsText; Snippet = 'append_end_game_gate_prerequisite' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_packs.lua"; Text = $scienceText; Snippet = 'end_game_science_pack' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'icon_candidates={' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'inactive_mod_asset="space-age"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '__space-age__/graphics/technology/processing-unit-productivity.png' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '__space-age__/graphics/technology/steel-plate-productivity.png' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '__space-age__/graphics/technology/low-density-structure-productivity.png' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '__space-age__/graphics/technology/plastics-productivity.png' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '__space-age__/graphics/technology/rocket-fuel-productivity.png' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '__space-age__/graphics/technology/research-productivity.png' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '{technology="research-productivity", required_mod="space-age"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '{technology="space-science-pack"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '{technology="processing-unit"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'native_owner_binding("steel-plate-productivity", {"steel-plate"})' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_rocket_fuel = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_thruster_fuel_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_thruster_oxidizer_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_oil_processing_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_oil_cracking_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_lubricant_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_sulfuric_acid_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'overlay_loader.get("air-scrubbing")' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_air_scrubbing_clean_filter = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'mods_any = air_scrubbing_overlay.applies_when.mods' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'generation_requirements = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'manifest_id = air_scrubbing_capability.stream.id' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'exact_recipe_patterns(air_scrubbing_capability.exact_recipes)' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_ash_separation = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'overlay_loader.get("atan-ash")' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'mods_any = atan_ash_overlay.applies_when.mods' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'manifest_id = atan_ash_capability.stream.id' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'exact_recipe_patterns(atan_ash_capability.exact_recipes)' },
    @{ File = "prototypes\mir\compatibility\overlays\atan_ash.lua"; Text = (Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\compatibility\overlays\atan_ash.lua")); Snippet = '"mir-prod-atan-ash-separation"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'local function space_age_setting_visibility()' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'hidden_reason = "space-age-not-active"' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'local function space_age_setting_visibility()' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'hidden_reason = "space-age-not-active"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_ash_separation = "Ash separation productivity"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '"aai-turbo-loader"' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_selector.lua"; Text = $scienceSelectorText; Snippet = 'desired == "derive-from-unlocks"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_air_scrubbing_clean_filter = "Air Scrubbing clean-filter productivity"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '{technology = "oil-processing"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '"^acid%-neutralisation$"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '"^acid%-neutralization$"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '{fluid = "sulfuric-acid"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'fluids = {"thruster-fuel"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '"^simple%-coal%-liquefaction$"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_walls = { icon_tech="gate", icon_item="stone-wall", groups = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'technology = "elevated-rail", required_mod = "elevated-rails"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'inactive_mod_asset = "elevated-rails"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'change = 0.05, items = { "rail-support" }' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'change = 0.02, items = { "rail-ramp" }' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_heavy_ammo = { icon_item="cannon-shell", groups = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'items={"artillery-shell","railgun-ammo"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '^omega%-drill$' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '^omega%-tau$' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = '{technology = "electric-weapons-damage-1", required_mod = "space-age"}' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = '__space-age__/graphics/technology/electric-weapons-damage.png' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = '{technology = "discharge-defense-equipment"}' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'technology-description.more-infinite-research.electric_shooting_speed' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'technology-description.more-infinite-research.flamethrower_shooting_speed' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'type = "laboratory-productivity", modifier = 0.10' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'skip_if_technology_effects = {' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'technology = "laboratory-productivity-4", type = "laboratory-productivity", modifier = 0.10, max_level = "infinite"' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'technology = "worker-robots-battery-6", type = "worker-robot-battery", modifier = 0.70, max_level = "infinite"' },
    @{ File = "prototypes\mir\presentation\icon_builder.lua"; Text = $technologyIconsText; Snippet = 'battery = "__core__/graphics/icons/technology/constants/constant-battery.png"' },
    @{ File = "prototypes\mir\presentation\icon_builder.lua"; Text = $technologyIconsText; Snippet = 'if t == "worker-robot-battery" then return "battery" end' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = '{technology = "research-productivity", required_mod = "space-age"}' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = '{technology = "military-science-pack"}' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'ammo_category = "tesla", modifier = 0.1' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'ammo_category = "electric", modifier = 0.1' },
    @{ File = "prototypes\mir\presentation\icon_builder.lua"; Text = $technologyIconsText; Snippet = 'local function strip_constant_overlays(icons)' },
    @{ File = "prototypes\mir\presentation\icon_builder.lua"; Text = $technologyIconsText; Snippet = 'local function resolve_icon_candidate(candidate)' },
    @{ File = "prototypes\mir\presentation\icon_builder.lua"; Text = $technologyIconsText; Snippet = 'function I.icon_source_for_stream(stream)' },
    @{ File = "prototypes\mir\presentation\icon_builder.lua"; Text = $technologyIconsText; Snippet = 'mir-use-installed-space-age-icons' },
    @{ File = "prototypes\mir\presentation\icon_builder.lua"; Text = $technologyIconsText; Snippet = 'local function icon_from_fluid(name)' },
    @{ File = "prototypes\mir\capabilities\recipe_productivity\recipe_matching.lua"; Text = $recipeMatchingText; Snippet = 'add_pattern_outputs(want, options.fluid_patterns, lookup.each_fluid_prototype)' },
    @{ File = "prototypes\mir\platform\factorio\prototype_lookup.lua"; Text = $prototypeLookupText; Snippet = 'function L.fluid_prototype(name)' },
    @{ File = "prototypes\mir\planner\requirements.lua"; Text = $plannerRequirementsText; Snippet = 'required_fluids' },
    @{ File = "prototypes\mir\planner\requirements.lua"; Text = $plannerRequirementsText; Snippet = 'technology_requirements.skip_reason(spec)' },
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.mir.settings.pipeline_extent").multiplier(value)' },
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.mir.compatibility.diagnostics.registry").emit_all()' },
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'if multiplier ~= 1 then' },
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.mir.pipeline.extent").apply(multiplier)' },
    @{ File = "prototypes\mir\settings\pipeline_extent.lua"; Text = $pipelineExtentSettingsText; Snippet = 'S.default_value = "100"' },
    @{ File = "prototypes\mir\settings\pipeline_extent.lua"; Text = $pipelineExtentSettingsText; Snippet = 'S.allowed_values = {"1000", "750", "500", "400", "300", "250", "200", "150", "125", "100", "75", "50", "25"}' },
    @{ File = "prototypes\mir\settings\pipeline_extent.lua"; Text = $pipelineExtentSettingsText; Snippet = 'function S.parse(value)' },
    @{ File = "prototypes\mir\settings\pipeline_extent.lua"; Text = $pipelineExtentSettingsText; Snippet = 'if type(value) == "number" then return value / 100 end' },
    @{ File = "prototypes\mir\settings\pipeline_extent.lua"; Text = $pipelineExtentSettingsText; Snippet = 'if numeric > 10 then return numeric / 100 end' },
    @{ File = "prototypes\mir\pipeline\extent.lua"; Text = $pipelineExtentText; Snippet = 'DEFAULT_PIPELINE_EXTENT = 320' },
    @{ File = "prototypes\mir\pipeline\extent.lua"; Text = $pipelineExtentText; Snippet = 'MAX_PIPELINE_EXTENT = 4294967295' },
    @{ File = "prototypes\mir\pipeline\extent.lua"; Text = $pipelineExtentText; Snippet = 'if multiplier == 1 then return end' },
    @{ File = "prototypes\mir\report\diagnostics_sink.lua"; Text = $diagnosticsText; Snippet = 'icons.icon_source_for_stream(spec or {})' },
    @{ File = "prototypes\mir\presentation\icon_builder.lua"; Text = $technologyIconsText; Snippet = 'local out = strip_constant_overlays(base_icons)' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityStreamsText; Snippet = '"%-incineration$"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityStreamsText; Snippet = '"%-incinerate$"' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_generated_icon_badge(tech_name, tech)' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_no_space_age_icon_path_in_base(tech_name, tech)' },
    @{ File = "fixtures\assert-generated-prerequisite-safety\data-final-fixes.lua"; Text = $generatedPrerequisiteFixtureText; Snippet = 'initial_status ~= "initial"' },
    @{ File = "fixtures\assert-generated-prerequisite-safety\data-final-fixes.lua"; Text = $generatedPrerequisiteFixtureText; Snippet = 'mir-fixture-custom-unlocker-a' },
    @{ File = "fixtures\assert-generated-prerequisite-safety\data-final-fixes.lua"; Text = $generatedPrerequisiteFixtureText; Snippet = 'mir-fixture-self-lock-science-pack' },
    @{ File = "fixtures\assert-generated-prerequisite-safety\data-final-fixes.lua"; Text = $generatedPrerequisiteFixtureText; Snippet = 'mir-fixture-cycle-science-pack-a' },
    @{ File = "fixtures\assert-generated-prerequisite-safety\data-final-fixes.lua"; Text = $generatedPrerequisiteFixtureText; Snippet = 'missing-research-mechanism' },
    @{ File = "fixtures\assert-generated-prerequisite-safety\data-updates.lua"; Text = $generatedPrerequisiteSetupText; Snippet = 'worker-robots-storage-3' },
    @{ File = "fixtures\assert-generated-prerequisite-safety\data-updates.lua"; Text = $generatedPrerequisiteSetupText; Snippet = 'automation_science.enabled = false' },
    @{ File = "fixtures\assert-generated-prerequisite-safety\data-updates.lua"; Text = $generatedPrerequisiteSetupText; Snippet = 'automation_science_recipe.enabled = true' },
    @{ File = "fixtures\assert-generated-prerequisite-safety\data-final-fixes.lua"; Text = $generatedPrerequisiteFixtureText; Snippet = 'base extension was emitted from disabled worker-robots-storage-3' },
    @{ File = "fixtures\assert-generated-prerequisite-safety\data-final-fixes.lua"; Text = $generatedPrerequisiteFixtureText; Snippet = 'disabled vanilla automation-science-pack technology was unexpectedly re-enabled' },
    @{ File = "fixtures\assert-generated-prerequisite-safety\control.lua"; Text = $generatedPrerequisiteRuntimeText; Snippet = 'force.research_all_technologies()' },
    @{ File = "prototypes\mir\index\recipe_unlocks.lua"; Text = $recipeUnlockIndexText; Snippet = 'function M.for_recipe(recipe_name)' },
    @{ File = "prototypes\mir\capabilities\science_integration"; Text = $scienceText; Snippet = 'S.researchable_unlockers_for_recipe = ready(pack_production_reachability.researchable_unlockers_for_recipe)' },
    @{ File = "prototypes\mir\capabilities\science_integration"; Text = $scienceText; Snippet = 'context:set_service(SERVICE_PREFIX .. "pack_production_status",' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_selector.lua"; Text = $scienceSelectorText; Snippet = 'science.researchable_unlockers_for_recipe(recipe_name)' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_selector.lua"; Text = $scienceSelectorText; Snippet = 'research_platform = {"space-science-pack", "cryogenic-science-pack"}' },
    @{ File = "prototypes\mir\planner\prerequisites.lua"; Text = $plannerPrerequisitesText; Snippet = 'science.researchable_unlockers_for_recipe(recipe_name)' },
    @{ File = "prototypes\mir\planner\requirements.lua"; Text = $plannerRequirementsText; Snippet = 'science.technology_researchability_reason(tech_name)' },
    @{ File = "fixtures\rigor-late-recipe-removal\data-final-fixes.lua"; Text = $lateRecipeRemovalFixtureText; Snippet = 'data.raw.recipe[target] = nil' },
    @{ File = "fixtures\rigor-late-recipe-removal\data-final-fixes.lua"; Text = $lateRecipeRemovalFixtureText; Snippet = 'microculture-vat-breeding' },
    @{ File = "fixtures\rigor-late-recipe-removal\data-final-fixes.lua"; Text = $lateRecipeRemovalFixtureText; Snippet = 'example-culture-incinerate' },
    @{ File = "fixtures\rigor-late-recipe-removal\data.lua"; Text = $lateRecipeRemovalDataText; Snippet = 'mir-fixture-normal-crafting' },
    @{ File = "fixtures\space-exploration-recipe-removal\data-final-fixes.lua"; Text = $spaceExplorationRemovalFixtureText; Snippet = 'kr-copper-cable-from-copper-ore' },
    @{ File = "fixtures\space-exploration-recipe-removal\data-final-fixes.lua"; Text = $spaceExplorationRemovalFixtureText; Snippet = 'MIR loaded before Space Exploration finalized its recipe removals' },
    @{ File = "fixtures\assert-final-recipe-effect-integrity\data-final-fixes.lua"; Text = $finalRecipeEffectFixtureText; Snippet = 'references missing recipe' },
    @{ File = "fixtures\assert-final-recipe-effect-integrity\data-final-fixes.lua"; Text = $finalRecipeEffectFixtureText; Snippet = 'valid base copper cable productivity was not retained' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'mir-use-installed-space-age-icons' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_icon_path("recipe-prod-research_electric_shooting_speed-1", "__space-age__/graphics/technology/electric-weapons-damage.png")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_item_icon("recipe-prod-research_heavy_ammo-1", "cannon-shell")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_technology_icon("recipe-prod-research_electric_shooting_speed-1", "electric-weapons-damage-1")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_technology_icon("recipe-prod-research_walls-1", "gate")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_technology_icon("recipe-prod-research_lab_productivity-1", "military-science-pack")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_technology_icon("recipe-prod-research_rocket_fuel-1", "rocket-fuel")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_technology_icon("recipe-prod-research_steel-1", "steel-processing")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = '{ recipe = "pentapod-egg", owner = "recipe-prod-research_breeding-1", change = 0.10 }' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = '{ recipe = "nutrients-from-bioflux", owner = "recipe-prod-research_nutrients-1", change = 0.10 }' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = '{ recipe = "capture-robot-rocket", owner = "recipe-prod-research_capture_robot_rockets-1", change = 0.10 }' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = '{ recipe = "ice-platform", owner = "recipe-prod-research_platform-1", change = 0.10 }' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = '{ recipe = "space-platform-foundation", owner = "recipe-prod-research_platform-1", change = 0.05 }' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_recipe_not_owned_by("nutrients-from-spoilage", "recipe-prod-research_nutrients-1")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_technology_has_science("recipe-prod-research_nutrients-1"' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_technology_lacks_science("recipe-prod-research_platform-1"' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_native_follower_robot_continuation()' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'technology.unit.count_formula ~= "1000*(L-4)"' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'effect_type == "laboratory-productivity"' },
    @{ File = "fixtures\assert-fluid-productivity\data-final-fixes.lua"; Text = $fluidProductivityFixtureText; Snippet = 'recipe-prod-research_oil_processing_productivity-1' },
    @{ File = "fixtures\assert-fluid-productivity\data-final-fixes.lua"; Text = $fluidProductivityFixtureText; Snippet = 'recipe-prod-research_thruster_fuel_productivity-1' },
    @{ File = "fixtures\assert-pipeline-extent\data-final-fixes.lua"; Text = $pipelineExtentFixtureText; Snippet = 'DEFAULT_PIPELINE_EXTENT = 320' },
    @{ File = "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua"; Text = $airScrubbingFixtureText; Snippet = 'recipe-prod-research_air_scrubbing_clean_filter-1' },
    @{ File = "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua"; Text = $airScrubbingFixtureText; Snippet = 'atan-pollution-filter-cleaning' },
    @{ File = "fixtures\atan-ash\data.lua"; Text = $atanAshFixtureText; Snippet = 'atan-ash-seperation' },
    @{ File = "fixtures\atan-ash\data.lua"; Text = $atanAshFixtureText; Snippet = 'atan-foundation-from-ash' },
    @{ File = "fixtures\assert-atan-ash-separation\data-final-fixes.lua"; Text = $atanAshAssertText; Snippet = 'recipe-prod-research_ash_separation-1' },
    @{ File = "fixtures\assert-atan-ash-separation\data-final-fixes.lua"; Text = $atanAshAssertText; Snippet = 'atan-landfill-from-ash' },
    @{ File = "fixtures\assert-aai-loader-belt-productivity\data-final-fixes.lua"; Text = $aaiLoaderFixtureText; Snippet = 'aai-turbo-loader' },
    @{ File = "fixtures\assert-big-mining-drill-productivity\data-final-fixes.lua"; Text = $bigMiningDrillFixtureText; Snippet = 'big-mining-drill should use +0.05' },
    @{ File = "fixtures\assert-semantic-family-attach\data-final-fixes.lua"; Text = $semanticFamilyFixtureText; Snippet = 'attachment-only default emitted generated family technology' },
    @{ File = "fixtures\assert-atan-nuclear-science-productivity\data-final-fixes.lua"; Text = $atanNuclearScienceFixtureText; Snippet = 'nuclear-science-pack did not receive science-pack productivity' },
    @{ File = "fixtures\capability-negative-cases\data.lua"; Text = $capabilityNegativeFixtureText; Snippet = 'mir-loader-like-container' },
    @{ File = "fixtures\capability-negative-cases\data.lua"; Text = $capabilityNegativeFixtureText; Snippet = 'maximum_productivity = 0' },
    @{ File = "fixtures\assert-capability-negative-cases\data-final-fixes.lua"; Text = $capabilityNegativeAssertText; Snippet = 'denied_recipes' },
    @{ File = "fixtures\assert-capability-negative-cases\data-final-fixes.lua"; Text = $capabilityNegativeAssertText; Snippet = 'REVIEW_REQUIRED' },
    @{ File = "prototypes\mir\index\recipe_risk_facts.lua"; Text = $recipeRiskFactsText; Snippet = 'risk_fingerprint' },
    @{ File = "prototypes\mir\index\recipe_risk_facts.lua"; Text = $recipeRiskFactsText; Snippet = 'ambiguous_placeable_output' },
    @{ File = "fixtures\assert-better-bot-battery-skip\data-final-fixes.lua"; Text = $betterBotBatteryFixtureText; Snippet = 'recipe-prod-research_robot_battery-1' },
    @{ File = "fixtures\assert-better-bot-battery-skip\data-final-fixes.lua"; Text = $betterBotBatteryFixtureText; Snippet = 'worker-robots-battery-6' },
    @{ File = "prototypes\mir\policy\weapon_speed.lua"; Text = $weaponSpeedText; Snippet = 'tech.unit and tech.unit.count_formula' },
    @{ File = "prototypes\mir\policy\weapon_speed.lua"; Text = $weaponSpeedText; Snippet = 'if mode == "off" then return {} end' },
    @{ File = "prototypes\mir\policy\weapon_speed.lua"; Text = $weaponSpeedText; Snippet = 'native_effect_coverage.technology_has_effect_identity' },
    @{ File = "prototypes\mir\policy\weapon_speed.lua"; Text = $weaponSpeedText; Snippet = 'generated_registry.contains(name)' },
    @{ File = "prototypes\mir\domain\facts\generated_technology_registry.lua"; Text = $generatedRegistryText; Snippet = 'function M.contains(name)' },
    @{ File = "prototypes\mir\policy\native_effect_coverage.lua"; Text = $nativeEffectCoverageText; Snippet = 'science.technology_is_researchable(name)' },
    @{ File = "prototypes\mir\policy\native_effect_coverage.lua"; Text = $nativeEffectCoverageText; Snippet = 'technology.max_level ~= "infinite"' },
    @{ File = "fixtures\assert-weapon-speed-safety\data-final-fixes.lua"; Text = $weaponSpeedFixtureText; Snippet = 'weapon-shooting-speed-5' },
    @{ File = "fixtures\assert-weapon-speed-safety\data-final-fixes.lua"; Text = $weaponSpeedFixtureText; Snippet = 'mir-fixture-external-weapon-speed-owner' },
    @{ File = "fixtures\assert-weapon-speed-safety\data-final-fixes.lua"; Text = $weaponSpeedFixtureText; Snippet = 'mir-fixture-unreachable-weapon-speed-owner' },
    @{ File = "fixtures\assert-weapon-speed-safety\data-final-fixes.lua"; Text = $weaponSpeedFixtureText; Snippet = 'weapon-shooting-speed-99' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = '[modifier-description]' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.electric_shooting_speed=' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.flamethrower_shooting_speed=' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.research_heavy_ammo=Cannon shell productivity' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.research_lab_productivity=Research productivity' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.research_oil_processing_productivity=Oil processing productivity' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.research_thruster_fuel_productivity=Thruster fuel productivity' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.lab_productivity=Increases research progress gained from each consumed science pack' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-use-installed-space-age-icons=[font=default-bold][color=cyan]Compatibility:[/color][/font] Use installed DLC icons in base games' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-automatic-productivity-action=[font=default-bold][color=green]Main:[/color][/font] Automatic recipe support' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-automatic-create-research=[font=default-bold][color=green]Main:[/color][/font] Allow new research creation' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-automatic-require-reviewed-data=[font=default-bold][color=green]Main:[/color][/font] Require reviewed data for new research' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-automatic-productivity-action-disabled=Disabled' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-automatic-productivity-action-preview=Preview changes' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-automatic-productivity-action-apply=Apply safe changes' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'This controls action, not strength or maturity; the creation checkboxes below are separate.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'MIR never creates one technology per mod or recipe' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'On permits only provider families marked reviewed and backed by applicable exact-version evidence, so experimental families are skipped.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'For the broadest experimental behavior, enable research creation and turn this requirement off.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-pipeline-extent-multiplier=[font=default-bold][color=cyan]Compatibility:[/color][/font] Pipeline extent multiplier' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'Factorio cannot recover gracefully from missing icon files during prototype loading.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'flamethrower-shooting-speed-bonus=Flamethrower shooting speed: +__1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'electric-shooting-speed-bonus=Electric shooting speed: +__1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'tesla-shooting-speed-bonus=Tesla shooting speed: +__1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-configured=Configured packs' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-space=Add space science' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-space-and-promethium=Add space + promethium' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-space-age-progression=Space Age progression' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-official-progression=Official progression' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-mod-progression=Modded progression' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-all-official=All official science packs' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-all=All lab science packs' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = '[string-mod-setting-description]' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = "mir-science-pack-ingredient-policy-configured=Use each generated technology's configured science packs without optional ingredient expansion. MIR default." },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-lab-incompatibility-policy-reduce=Use researchable packs' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-lab-incompatibility-policy-skip=Skip unsupported techs' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-lab-incompatibility-policy-engine-default=No MIR adjustment' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-lab-incompatibility-policy-reduce=Keep the technology by reducing its science packs to the largest set accepted by an active lab. Safest default for mod packs.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-lab-incompatibility-policy-engine-default=Never rewrite the selected science-pack set.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'ips-enable-stream=[font=default-bold]__1__[/font] — enable' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-max-level=[font=default-bold]Infinite __1__[/font] — max level' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'ips-research-time-stream=[font=default-bold]__1__[/font] — research time' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'ips-require-space-gate=[font=default-bold][color=green]Main:[/color][/font] Require game completion before generated technologies' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy=[font=default-bold][color=green]Main:[/color][/font] Science packs for generated technologies' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-lab-incompatibility-policy=[font=default-bold][color=green]Main:[/color][/font] Lab compatibility for generated technologies' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prefer-this-mod-for-competing-techs=[font=default-bold][color=green]Main:[/color][/font] Prefer MIR for duplicate infinite research' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-adjust-vanilla-weapon-speed-techs=[font=default-bold][color=cyan]Compatibility:[/color][/font] Rocket/cannon speed cleanup' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-debug-generation-report=[font=default-bold][color=yellow]Diagnostics:[/color][/font] Generated and skipped technologies' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-note-experimental-spoilage=Risky technology. Enabled by default.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-note-agriculture-growth=Applies to newly planted agricultural tower crops.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-note-inserter-capacity=Risky technology. Enabled by default.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-note-risk-factory-disruptive=Risky technology. Enabled by default.' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'mod-setting-description.mir-note-experimental-spoilage' },
    @{ File = "prototypes\mir\settings\defaults.lua"; Text = $defaultsText; Snippet = 'mod-setting-description.mir-note-agriculture-growth' },
    @{ File = "prototypes\mir\settings\defaults.lua"; Text = $defaultsText; Snippet = 'mod-setting-description.mir-note-inserter-capacity' },
    @{ File = "prototypes\mir\settings\defaults.lua"; Text = $defaultsText; Snippet = 'research_lab_productivity = {' }
  )

  if ($isReducedLegacyLine -or $isLegacyFactorio20) {
    $legacyForbiddenCargoSnippets = @(
      'type = "max-cargo-bay-unloading-distance"',
      'type = "cargo-landing-pad-count"'
    )
    foreach ($snippet in $legacyForbiddenCargoSnippets) {
      if ($directEffectsText.Contains($snippet)) {
        throw "Factorio $($repoInfo.factorio_version) must not include Factorio 2.1-only cargo technology modifier in prototypes\streams\direct-effects.lua: $snippet"
      }
    }
  } else {
    $requiredSnippets += @(
      @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_cargo_landing_pad_count = "Cargo landing pad count"' },
      @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'cargo-landing-pad-count=Cargo landing pads per surface: +__1__' },
      @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-note-cargo-pad-count=Special Space Age logistics research.' },
      @{ File = "prototypes\mir\settings\defaults.lua"; Text = $defaultsText; Snippet = 'mod-setting-description.mir-note-cargo-pad-count' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'research_cargo_landing_pad_count = {' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'required_mods = {"space-age"}' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'required_technologies = {"rocket-silo"}' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'icon_tech = "landing-pad-unloading-bay"' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'icon_tech = "space-platform"' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'science_packs = "all-official"' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'type = "max-cargo-bay-unloading-distance", modifier = 10' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'type = "cargo-landing-pad-count", modifier = 1' }
    )
  }

  if ($isReducedLegacyLine) {
    $requiredSnippets = @(
      $requiredSnippets | Where-Object {
        -not (
          $_.File -eq "prototypes\streams\direct-effects.lua" -and
          $_.Snippet -in @(
            'local function space_age_setting_visibility()',
            'hidden_reason = "space-age-not-active"',
            "ui_visibility = {",
            "generation_requirements = {",
            '{technology = "electric-weapons-damage-1", required_mod = "space-age"}',
            '__space-age__/graphics/technology/electric-weapons-damage.png',
            '{technology = "research-productivity", required_mod = "space-age"}',
            'ammo_category = "tesla", modifier = 0.1'
          )
        ) -and -not (
          $_.File -eq "prototypes\mir\settings\defaults.lua" -and
          $_.Snippet -in @(
            "mod-setting-description.mir-note-experimental-spoilage",
            "mod-setting-description.mir-note-agriculture-growth"
          )
        )
      }
    )
  }

  if ($isReducedLegacyLine) {
    $reducedForbiddenDirectEffectSnippets = @(
      '__space-age__/',
      '{technology = "electric-weapons-damage-1", required_mod = "space-age"}',
      '{technology = "research-productivity", required_mod = "space-age"}',
      'ammo_category = "tesla"',
      '"agricultural-science-pack"',
      '"electromagnetic-science-pack"',
      '"cryogenic-science-pack"'
    )
    foreach ($snippet in $reducedForbiddenDirectEffectSnippets) {
      if ($directEffectsText.Contains($snippet)) {
        throw "Factorio $($repoInfo.factorio_version) direct-effect streams must not carry newer-line surface '$snippet'."
      }
    }
  }

  foreach ($check in $requiredSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing science-pack progression setting wiring in $($check.File): $($check.Snippet)"
    }
  }

  $duplicatedUnlockScan = 'effect.type == "unlock-recipe" and effect.recipe == recipe_name'
  foreach ($consumer in @(
    @{ File = "prototypes\mir\capabilities\science_integration\science_selector.lua"; Text = $scienceSelectorText },
    @{ File = "prototypes\mir\planner\prerequisites.lua"; Text = $plannerPrerequisitesText }
  )) {
    if ($consumer.Text.Contains($duplicatedUnlockScan)) {
      throw "Recipe unlock facts must come from the shared index: $($consumer.File)"
    }
  }

  foreach ($consumer in @(
    @{ File = "prototypes\mir\capabilities\recipe_productivity\recipe_matching.lua"; Text = $recipeMatchingText },
    @{ File = "prototypes\mir\capabilities\science_integration\recipe_unlock_facts.lua"; Text = $scienceText },
    @{ File = "prototypes\mir\index\registry_builder.lua"; Text = (Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\index\registry_builder.lua")) },
    @{ File = "prototypes\mir\compatibility\diagnostics\exact_recipe_policy.lua"; Text = (Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\compatibility\diagnostics\exact_recipe_policy.lua")) }
  )) {
    if ($consumer.Text.Contains('data_raw.prototypes("recipe")')) {
      throw "Recipe consumers must query the canonical build-once fact catalog: $($consumer.File)"
    }
  }
  $recipeFactsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\index\recipe_facts.lua")
  if (-not $recipeFactsText.Contains("function M.candidate_names") -or -not $recipeFactsText.Contains("function M.scan_count")) {
    throw "Canonical recipe facts must expose indexed candidate queries and scan-count evidence."
  }
  if (-not $generationIntegrityFixtureText.Contains("canonical_recipe_facts.scan_count() ~= 1")) {
    throw "Generation integrity fixture must prove one canonical recipe prototype scan."
  }

  $settingsPresetsPath = Join-Path $repo "prototypes\settings-presets.lua"
  if (Test-Path -LiteralPath $settingsPresetsPath) {
    throw "Removed settings preset module should not exist: prototypes\settings-presets.lua"
  }

  $forbiddenSnippets = @(
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'mir-settings-mode' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'mir-enable-policy-' },
    @{ File = "prototypes\mir\settings\resolver.lua"; Text = $settingsResolverText; Snippet = 'settings-presets' },
    @{ File = "prototypes\mir\settings\resolver.lua"; Text = $settingsResolverText; Snippet = 'Force enabled' },
    @{ File = "prototypes\mir\runtime\settings_resolver.lua"; Text = $runtimeSettingsResolverText; Snippet = 'settings-presets' },
    @{ File = "prototypes\mir\runtime\settings_resolver.lua"; Text = $runtimeSettingsResolverText; Snippet = 'mir-enable-policy-' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-settings-mode=' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-enable-policy-stream=' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-enable-policy-base-tech=' }
  )
  foreach ($check in $forbiddenSnippets) {
    if ($check.Text.Contains($check.Snippet)) {
      throw "Removed preset/enable-policy wiring remains in $($check.File): $($check.Snippet)"
    }
  }

  foreach ($weaponSpeedStream in @("research_rocket_shooting_speed", "research_cannon_shooting_speed")) {
    $match = [regex]::Match($defaultsText, "(?s)$weaponSpeedStream\s*=\s*\{.*?science_packs\s*=\s*\{(?<packs>.*?)\n\s*\}")
    if (-not $match.Success) {
      throw "Missing explicit default science pack list for $weaponSpeedStream in prototypes/mir/settings/defaults.lua."
    }
    $packs = $match.Groups["packs"].Value
    if ($isReducedLegacyLine) {
      foreach ($newerPack in @("agricultural-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack")) {
        if ($packs.Contains($newerPack)) {
          throw "$weaponSpeedStream prototypes/mir/settings/defaults.lua science packs must not include $newerPack on Factorio $($repoInfo.factorio_version)."
        }
      }
    } else {
      if (-not $packs.Contains("electromagnetic-science-pack")) {
        throw "$weaponSpeedStream prototypes/mir/settings/defaults.lua science packs must include electromagnetic-science-pack."
      }
      if ($packs.Contains("agricultural-science-pack")) {
        throw "$weaponSpeedStream prototypes/mir/settings/defaults.lua science packs must not include agricultural-science-pack."
      }
    }
  }

  if ($isFactorio21Line) {
    if ($defaultsText -notmatch '(?s)research_cargo_bay_unloading_distance\s*=\s*\{.*?research_time\s*=\s*120') {
      throw "Cargo bay unloading distance default research time must be 120 seconds."
    }
    if ($defaultsText -notmatch '(?s)research_cargo_landing_pad_count\s*=\s*\{.*?research_time\s*=\s*240') {
      throw "Cargo landing pad count default research time must be 240 seconds."
    }
  }

  $promotedSpecialStreams = @("research_character_reach")
  if (-not $isReducedLegacyLine) {
    $promotedSpecialStreams = @(
      "research_breeding",
      "research_agricultural_growth_speed",
      "research_cargo_bay_unloading_distance",
      "research_cargo_landing_pad_count",
      "research_character_reach"
    )
  }

  foreach ($promotedSpecialStream in $promotedSpecialStreams) {
    if ($defaultsText -notmatch "(?s)$promotedSpecialStream\s*=\s*\{.*?settings_priority\s*=\s*`"top`"") {
      throw "$promotedSpecialStream must stay in the enabled special technology settings bucket."
    }
    if ($defaultsText -notmatch "(?s)$promotedSpecialStream\s*=\s*\{.*?enabled\s*=\s*true") {
      throw "$promotedSpecialStream must be enabled by default."
    }
  }

  if ($defaultsText -notmatch '(?s)\["inserter-capacity-bonus"\]\s*=\s*\{.*?enabled\s*=\s*true') {
    throw "Inserter capacity bonus must be enabled by default."
  }
  if ($defaultsText -notmatch '(?s)\["inserter-capacity-bonus"\]\s*=\s*\{.*?technology_risk\s*=\s*\{.*?class\s*=\s*"factory-disruptive"') {
    throw "Inserter capacity bonus must stay in the factory-disruptive settings bucket independently of its default."
  }
}

