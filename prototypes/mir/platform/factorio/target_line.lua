local M = {}

M.factorio_version = "1.1"

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

local legacy_technology_overlay_layers = {
  -- Mirror Factorio 1.1's high-resolution util.technology_icon_constant_*
  -- badge layers. The smaller effect-constant files are utility sprites for
  -- the effects panel, not technology tile overlays.
  ["laboratory-productivity"] = "__core__/graphics/icons/technology/constants/constant-mining-productivity.png",
  ["recipe-productivity"] = "__core__/graphics/icons/technology/constants/constant-mining-productivity.png",
  speed = "__core__/graphics/icons/technology/constants/constant-speed.png",
  ["crafting-speed"] = "__core__/graphics/icons/technology/constants/constant-speed.png",
  ["movement-speed"] = "__core__/graphics/icons/technology/constants/constant-movement-speed.png",
  mining = "__core__/graphics/icons/technology/constants/constant-mining.png",
  battery = "__core__/graphics/icons/technology/constants/constant-battery.png",
  capacity = "__core__/graphics/icons/technology/constants/constant-capacity.png",
  damage = "__core__/graphics/icons/technology/constants/constant-damage.png",
  range = "__core__/graphics/icons/technology/constants/constant-range.png",
  ["braking-force"] = "__core__/graphics/icons/technology/constants/constant-braking-force.png",
  equipment = "__core__/graphics/icons/technology/constants/constant-equipment.png",
  count = "__core__/graphics/icons/technology/constants/constant-count.png"
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
  return effect_type ~= nil and not unsupported_effect_types[effect_type]
end

function M.global_setting_supported(name)
  return not omitted_global_settings[name]
end

function M.feature_enabled(name)
  return M.supports[name] == true
end

function M.technology_overlay_layer(overlay)
  local icon = legacy_technology_overlay_layers[overlay or "recipe-productivity"]
  if not icon then return nil end

  return {
    icon = icon,
    icon_size = 128,
    shift = {100, 100},
    floating = true
  }
end

return M
