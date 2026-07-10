local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")

local M = {}
local profile = target_profiles.current()

M.factorio_version = profile.factorio_version
M.supports = profile.features

local function to_set(values)
  local out = {}
  for _, value in ipairs(values or {}) do out[value] = true end
  return out
end

local unsupported_streams = to_set(profile.unsupported_streams)
local unsupported_required_mods = to_set(profile.unsupported_required_mods)
local unsupported_effect_types = to_set(profile.unsupported_effect_types)
local omitted_global_settings = to_set(profile.omitted_global_settings)

local legacy_technology_overlay_layers = {
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
    return M.feature_enabled("recipe_productivity")
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

function M.runtime_state_backend()
  return profile.runtime_state_backend
end

function M.science_family()
  return profile.science_family
end

function M.weapon_overlap_default()
  return profile.weapon_overlap_default
end

function M.technology_overlay_layer(overlay)
  if profile.technology_overlay_policy == "modern" then return nil end
  if profile.technology_overlay_policy == "none" then return false end

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
