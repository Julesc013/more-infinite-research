local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local deepcopy = require("prototypes.mir.core.deepcopy")
local effective_settings = require("prototypes.mir.settings.effective")
local prototype_limit_settings = require("prototypes.mir.settings.prototype_limits")

local P = {}

local effect_receiver_types = {
  "assembling-machine",
  "furnace",
  "rocket-silo",
  "lab",
  "mining-drill",
  "agricultural-tower"
}

local engine_defaults = {
  consumption_limits = { low = -0.8, high = 1000 },
  speed_limits = { low = -0.8, high = 1000 },
  quality_limits = { low = 0, high = 1000 }
}

local function selected(setting_key)
  local spec = prototype_limit_settings.settings[setting_key]
  if not spec then return nil end
  return prototype_limit_settings.value(setting_key, effective_settings.get(spec.name))
end

local function copy_range(current, defaults)
  local out = deepcopy(defaults)
  if type(current) == "table" then
    for key, value in pairs(current) do
      out[key] = value
    end
  end
  return out
end

local function ensure_effect_receiver(prototype)
  prototype.effect_receiver = deepcopy(prototype.effect_receiver or {})
  return prototype.effect_receiver
end

local function set_limit(receiver, field, side, value)
  local defaults = engine_defaults[field]
  receiver[field] = copy_range(receiver[field], defaults)
  receiver[field][side] = value
end

local function apply_recipe_productivity_cap(value)
  if value == nil then return 0 end

  local changed = 0
  for _, recipe in pairs(data_raw.prototypes("recipe")) do
    if type(recipe) == "table" and recipe.parameter ~= true and recipe.maximum_productivity ~= value then
      recipe.maximum_productivity = value
      changed = changed + 1
    end
  end
  return changed
end

local function apply_effect_receiver_limit(field, side, value)
  if value == nil then return 0 end

  local changed = 0
  for _, prototype_type in ipairs(effect_receiver_types) do
    for _, prototype in pairs(data_raw.prototypes(prototype_type)) do
      if type(prototype) == "table" then
        local receiver = ensure_effect_receiver(prototype)
        local old = receiver[field] and receiver[field][side]
        if old ~= value then
          set_limit(receiver, field, side, value)
          changed = changed + 1
        end
      end
    end
  end
  return changed
end

function P.apply()
  local changed = {
    productivity = apply_recipe_productivity_cap(selected("productivity")),
    efficiency = apply_effect_receiver_limit("consumption_limits", "low", selected("efficiency")),
    speed = apply_effect_receiver_limit("speed_limits", "high", selected("speed")),
    quality = apply_effect_receiver_limit("quality_limits", "high", selected("quality"))
  }

  if changed.productivity > 0 or changed.efficiency > 0 or changed.speed > 0 or changed.quality > 0 then
    log("[more-infinite-research] Applied prototype limits: productivity_recipes="
      .. tostring(changed.productivity)
      .. " efficiency_receivers="
      .. tostring(changed.efficiency)
      .. " speed_receivers="
      .. tostring(changed.speed)
      .. " quality_receivers="
      .. tostring(changed.quality)
      .. ".")
  end

  return changed
end

return P
