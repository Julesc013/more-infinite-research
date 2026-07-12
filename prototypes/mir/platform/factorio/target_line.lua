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

local supported_required_mods = to_set(profile.supported_required_mods)
local supported_effect_types = to_set(profile.supported_effect_types)

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
    if not supported_required_mods[mod_name] then return true end
  end
  return false
end

local function has_missing_positive_requirement(spec)
  local requirements = spec and spec.descriptor and spec.descriptor.targets
  if type(requirements) ~= "table" then return true end
  for _, feature in ipairs(requirements.requires_features or {}) do
    if not M.feature_enabled(feature) then return true end
  end
  for _, effect_type in ipairs(requirements.required_effect_types or {}) do
    if not supported_effect_types[effect_type] then return true end
  end
  return false
end

function M.stream_supported(key, spec)
  if has_unsupported_required_mod(spec) then return false end
  if has_missing_positive_requirement(spec) then return false end
  if not (spec and spec.direct_effects) then
    return M.feature_enabled("recipe_productivity")
  end
  return true
end

function M.effect_supported(effect)
  local effect_type = effect and effect.type
  if effect_type == nil then return false end
  if effect_type == "nothing" then return true end
  return supported_effect_types[effect_type] == true
end

function M.global_setting_supported(name)
  return type(name) == "string" and name ~= ""
end

function M.setting_supported(spec)
  if not spec or not M.global_setting_supported(spec.name) then return false end
  local requirements = spec.targets or {}
  for _, feature in ipairs(requirements.requires_features or {}) do
    if not M.feature_enabled(feature) then return false end
  end
  for _, effect_type in ipairs(requirements.required_effect_types or {}) do
    if not supported_effect_types[effect_type] then return false end
  end
  return true
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

function M.prototype_shapes()
  return profile.prototype_shapes
end

function M.expected_stream_count()
  return profile.expected_stream_count
end

function M.emitter_supported(name)
  for _, emitter in ipairs(profile.emitter_families or {}) do
    if emitter == name then return true end
  end
  return false
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
