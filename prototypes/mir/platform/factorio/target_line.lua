local M = {}

M.factorio_version = "2.1"

M.supports = {
  compatibility_repairs = true,
  pipeline_extent = true,
  prototype_limits = true,
  recipe_productivity = true,
  settings_profiles = true,
  scripted_techs = true,
  technology_constant_overlays = true,
  productivity_family_adoption = true
}

function M.stream_supported()
  return true
end

function M.effect_supported(effect)
  return effect and effect.type ~= nil
end

function M.global_setting_supported()
  return true
end

function M.feature_enabled(name)
  return M.supports[name] == true
end

function M.technology_overlay_layer()
  return nil
end

return M
