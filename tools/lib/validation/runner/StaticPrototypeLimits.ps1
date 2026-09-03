Invoke-RepoCheck "prototype limit settings are wired" {
  $settingsText = Get-MIRSettingsSourceText
  $settingsCatalogText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\catalog.lua")
  $effectContractsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\effect_contracts.lua")
  $streamDescriptorText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\domain\streams\descriptor.lua")
  $effectScalingText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\effect_scaling.lua")
  $dataFinalFixesText = Get-MIRDataFinalFixesSourceText
  $stepsText = (Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\stage\data_final_fixes_steps.lua")) + "`n" +
    (Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\pipeline\commands.lua"))
  $prototypeLimitSettingsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\prototype_limits.lua")
  $prototypeLimitPipelineText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\pipeline\prototype_limits.lua")
  $localeText = Get-Content -Raw -LiteralPath (Join-Path $repo "locale\en\more-infinite-research.cfg")
  $settingsManifestText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\settings.yml")
  $modulesManifestText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\modules.yml")
  $fixturesManifestText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\fixtures.yml")
  $prototypeLimitFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-prototype-limits\data-final-fixes.lua")

  $requiredSnippets = @(
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local prototype_limit_settings = require("prototypes.mir.settings.prototype_limits")' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'prototype_limit_settings.setting_prototypes()' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = 'name = "mir-prototype-productivity-cap"' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = 'name = "mir-prototype-efficiency-cap"' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = 'name = "mir-prototype-pollution-cap"' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = 'name = "mir-prototype-speed-cap"' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = 'name = "mir-prototype-speed-floor"' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = 'name = "mir-prototype-quality-cap"' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = 'positive_power_floor_setting_name = "mir-prototype-positive-power-floor"' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = 'S.recycling_return_accepted_import_values = {"percent-25"}' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = 'default_value = S.engine_default' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = '["percent-50"] = 0.5' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = '["percent-400"] = 4.0' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = '["saving-50"] = -0.5' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = '["saving-99"] = -0.99' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = '["bonus-50"] = 0.5' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = '["bonus-400"] = 4.0' },
    @{ File = "prototypes\mir\settings\prototype_limits.lua"; Text = $prototypeLimitSettingsText; Snippet = 'if type(raw_value) == "number" then return raw_value / 100 end' },
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'commands.run_all({return_snapshot = false})' },
    @{ File = "prototypes\mir\stage\data_final_fixes_steps.lua"; Text = $stepsText; Snippet = 'require("prototypes.mir.pipeline.prototype_limits").apply()' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'data_raw.prototypes("recipe")' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'recipe.parameter ~= true' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'recipe.maximum_productivity = value' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = '"agricultural-tower"' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'apply_effect_receiver_limit("consumption_limits", "low", selected("efficiency"))' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'apply_effect_receiver_limit("pollution_limits", "low", selected("pollution"))' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'apply_effect_receiver_limit("speed_limits", "high", selected("speed"))' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'apply_effect_receiver_limit("speed_limits", "low", selected("speed_floor"))' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'apply_recycling_return_chance(productivity_cap)' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'recipe.hidden ~= true or recipe.unlock_results ~= false' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'apply_effect_receiver_limit("quality_limits", "high", selected("quality"))' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'prototype.energy_usage = "1W"' },
    @{ File = "prototypes\mir\pipeline\prototype_limits.lua"; Text = $prototypeLimitPipelineText; Snippet = 'Applied prototype limits: productivity_recipes=' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-productivity-cap=[font=default-bold][color=orange]Limits:[/color][/font] Recipe productivity cap' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-efficiency-cap=[font=default-bold][color=orange]Limits:[/color][/font] Energy savings cap' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-pollution-cap=[font=default-bold][color=orange]Limits:[/color][/font] Pollution reduction cap' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-speed-cap=[font=default-bold][color=orange]Limits:[/color][/font] Speed effect cap' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-speed-floor=[font=default-bold][color=orange]Limits:[/color][/font] Minimum machine speed' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-recycling-return-chance=[font=default-bold][color=orange]Limits:[/color][/font] Recycler return rate' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-quality-cap=[font=default-bold][color=orange]Limits:[/color][/font] Quality effect cap' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-positive-power-floor=[font=default-bold][color=cyan]Compatibility:[/color][/font] Non-zero power floor' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-productivity-cap-engine-default=+300% (unchanged)' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-productivity-cap-percent-50=+50%' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-efficiency-cap-saving-99=-99%' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-efficiency-cap-engine-default=-80% (unchanged)' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-pollution-cap-saving-99=-99%' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'explicit 0W active energy_usage prototypes to 1W' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-speed-cap-engine-default=+100000% (unchanged)' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-speed-cap-bonus-400=+400%' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prototype-quality-cap-bonus-400=+400%' },
    @{ File = ".mir\settings.yml"; Text = $settingsManifestText; Snippet = 'prototype_limit_settings_default_to_engine_default: true' },
    @{ File = ".mir\settings.yml"; Text = $settingsManifestText; Snippet = 'energy_and_pollution_caps_are_separate: true' },
    @{ File = ".mir\settings.yml"; Text = $settingsManifestText; Snippet = 'positive_speed_cap_and_negative_speed_floor_are_separate: true' },
    @{ File = ".mir\settings.yml"; Text = $settingsManifestText; Snippet = 'automatic_recycling_return_is_total-output-inverse_and_never_buffs_vanilla: true' },
    @{ File = ".mir\settings.yml"; Text = $settingsManifestText; Snippet = 'numeric_dropdown_profile_imports_accept_valid_custom_percentages: true' },
    @{ File = ".mir\settings.yml"; Text = $settingsManifestText; Snippet = 'positive_power_floor_is_default_off_opt_in: true' },
    @{ File = ".mir\settings.yml"; Text = $settingsManifestText; Snippet = 'positive_power_floor_is_compatibility_section_setting: true' },
    @{ File = ".mir\modules.yml"; Text = $modulesManifestText; Snippet = 'prototypes/mir/settings/catalog.lua' },
    @{ File = ".mir\modules.yml"; Text = $modulesManifestText; Snippet = 'prototypes/mir/settings/prototype_limits.lua' },
    @{ File = ".mir\modules.yml"; Text = $modulesManifestText; Snippet = 'prototypes/mir/pipeline/prototype_limits.lua' },
    @{ File = ".mir\fixtures.yml"; Text = $fixturesManifestText; Snippet = 'prototype-limit-startup-overrides' },
    @{ File = ".mir\fixtures.yml"; Text = $fixturesManifestText; Snippet = 'settings-profile-roundtrip' },
    @{ File = "fixtures\assert-prototype-limits\data-final-fixes.lua"; Text = $prototypeLimitFixtureText; Snippet = 'iron-gear-wheel maximum_productivity' },
    @{ File = "fixtures\assert-prototype-limits\data-final-fixes.lua"; Text = $prototypeLimitFixtureText; Snippet = 'self-recycling production maximum_productivity' },
    @{ File = "fixtures\assert-prototype-limits\data-final-fixes.lua"; Text = $prototypeLimitFixtureText; Snippet = 'unrestricted module permissions did not open all recipe effect flags' },
    @{ File = "fixtures\assert-prototype-limits\data-final-fixes.lua"; Text = $prototypeLimitFixtureText; Snippet = 'consumption_limits.low' },
    @{ File = "fixtures\assert-prototype-limits\data-final-fixes.lua"; Text = $prototypeLimitFixtureText; Snippet = 'pollution_limits.low' },
    @{ File = "fixtures\assert-prototype-limits\data-final-fixes.lua"; Text = $prototypeLimitFixtureText; Snippet = 'generated recycling independent_probability' },
    @{ File = "fixtures\assert-prototype-limits\data-final-fixes.lua"; Text = $prototypeLimitFixtureText; Snippet = 'generated recycling maximum_productivity was changed' },
    @{ File = "fixtures\assert-prototype-limits\data-final-fixes.lua"; Text = $prototypeLimitFixtureText; Snippet = 'pre-existing high maximum_productivity' },
    @{ File = "fixtures\assert-prototype-limits\data-final-fixes.lua"; Text = $prototypeLimitFixtureText; Snippet = 'tier-4 module recipe was not discovered by module prototype tier' },
    @{ File = "fixtures\assert-prototype-limits\data-final-fixes.lua"; Text = $prototypeLimitFixtureText; Snippet = 'zero-watt beacon energy_usage' },
    @{ File = "fixtures\assert-prototype-limits\data-final-fixes.lua"; Text = $prototypeLimitFixtureText; Snippet = 'quality_limits.high' },
    @{ File = "prototypes\mir\settings\catalog.lua"; Text = $settingsCatalogText; Snippet = 'require("prototypes.mir.settings.effect_contracts")' },
    @{ File = "prototypes\mir\settings\effect_contracts.lua"; Text = $effectContractsText; Snippet = 'spec.descriptor.effect' },
    @{ File = "prototypes\mir\domain\streams\descriptor.lua"; Text = $streamDescriptorText; Snippet = 'change > anchor' },
    @{ File = "prototypes\mir\settings\effect_scaling.lua"; Text = $effectScalingText; Snippet = 'local effective_settings = require("prototypes.mir.settings.effective")' },
    @{ File = "scripts\Invoke-MIRValidation.ps1"; Text = (Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Invoke-MIRValidation.ps1")); Snippet = 'prototype-limit-overrides' }
  )

  foreach ($check in $requiredSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing prototype limit setting wiring in $($check.File): $($check.Snippet)"
    }
  }

  if ($settingsCatalogText.Contains('require("prototypes.mir.settings.effect_scaling")')) {
    throw "Settings catalog must depend on pure effect contracts, not runtime effect scaling."
  }
  if ($effectContractsText.Contains('require("prototypes.mir.settings.effective")')) {
    throw "Effect contracts must not import effective settings; catalog/profile loading would recurse."
  }

  if (-not $stepsText.Contains('["recipe-productivity-permissions"] = {phase = 12, dependencies = {"compatibility-repairs"}}') `
      -or -not $stepsText.Contains('["sanitize-input-technology-effects"] = {phase = 15, dependencies = {"recipe-productivity-permissions"}}') `
      -or -not $stepsText.Contains('["prototype-limits"] = {phase = 20, dependencies = {"compatibility-repairs", "module-permissions"}}') `
      -or -not $stepsText.Contains('["pipeline-extent"] = {phase = 20, dependencies = {"compatibility-repairs", "prototype-limits"}}') `
      -or -not $stepsText.Contains('["prepare-competing-productivity"] = {phase = 30, dependencies = {"pipeline-extent"}}')) {
    throw "Recipe permissions and prototype limits must run after compatibility repairs and before fact capture, planning, and recipe-cap diagnostics."
  }
}

