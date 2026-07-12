local M = {}

M.factorio_version = "0.14"

M.supports = {
  compatibility_repairs = false,
  pipeline_extent = false,
  prototype_limits = false,
  recipe_productivity = false,
  settings_profiles = false,
  scripted_techs = false,
  technology_constant_overlays = false,
  productivity_family_adoption = false
}

local unsupported_streams = {
  research_agricultural_growth_speed = true,
  research_cargo_bay_unloading_distance = true,
  research_cargo_landing_pad_count = true,
  research_spoilage_preservation = true
}

local unsupported_required_mods = {
  ["elevated-rails"] = true,
  quality = true,
  recycler = true,
  ["space-age"] = true
}

local unsupported_effect_types = {
  ["cargo-landing-pad-count"] = true,
  ["max-cargo-bay-unloading-distance"] = true
}

local supported_effect_types = {
  ["ammo-damage"] = true,
  ["gun-speed"] = true,
  ["inserter-stack-size-bonus"] = true,
  ["laboratory-speed"] = true,
  ["stack-inserter-capacity-bonus"] = true,
  ["turret-attack"] = true,
  ["worker-robot-speed"] = true,
  ["worker-robot-storage"] = true
}

local omitted_global_settings = {
  ["mir-pipeline-extent-multiplier"] = true,
  ["mir-prototype-productivity-cap"] = true,
  ["mir-prototype-efficiency-cap"] = true,
  ["mir-prototype-pollution-cap"] = true,
  ["mir-prototype-speed-cap"] = true,
  ["mir-prototype-quality-cap"] = true,
  ["mir-prototype-positive-power-floor"] = true,
  ["mir-settings-profile-import"] = true,
  ["mir-use-installed-space-age-icons"] = true
}

local function has_unsupported_required_mod(spec)
  for _, mod_name in ipairs((spec and spec.required_mods) or {}) do
    if unsupported_required_mods[mod_name] then return true end
  end
  return false
end

function M.stream_supported(key, spec)
  if unsupported_streams[key] then return false end
  if has_unsupported_required_mod(spec) then return false end
  if not (spec and spec.direct_effects) then
    return M.supports.recipe_productivity
  end
  return true
end

function M.effect_supported(effect)
  local effect_type = effect and effect.type
  return effect_type ~= nil and supported_effect_types[effect_type] == true and not unsupported_effect_types[effect_type]
end

function M.global_setting_supported(name)
  return not omitted_global_settings[name]
end

function M.feature_enabled(name)
  return M.supports[name] == true
end

function M.technology_overlay_layer()
  -- Factorio 0.14 does not ship the 1.1+ stock technology constant badge
  -- assets or a documented native modifier icon surface. Keep generated
  -- technologies on target-era technology art.
  return false
end

function M.fallback_technology_icon_size()
  return 128
end

function M.supports_native_infinite_technology()
  return false
end

function M.finite_research_count(count_formula)
  local leading = tonumber(string.match(tostring(count_formula or ""), "^([%d%.]+)"))
  if not leading or leading < 1 then return 1000 end
  return math.floor(leading + 0.5)
end

return M
