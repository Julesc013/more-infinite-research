local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local deepcopy = require("prototypes.mir.core.deepcopy")
local effective_settings = require("prototypes.mir.settings.effective")
local prototype_limit_settings = require("prototypes.mir.settings.prototype_limits")
local cap_scope = require("prototypes.mir.policy.productivity_cap_scope")

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
  pollution_limits = { low = -0.8, high = 1000 },
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
  local scoped = effective_settings.get(prototype_limit_settings.self_recycling_scope_setting_name) == true
  local approved = 0
  local rejected = 0
  for _, recipe in pairs(data_raw.prototypes("recipe")) do
    if type(recipe) == "table" and recipe.parameter ~= true then
      local should_apply = true
      if scoped and value > 3.0 then
        local safe = cap_scope.approve(recipe)
        should_apply = safe == true
        if should_apply then approved = approved + 1 else rejected = rejected + 1 end
      end
      if should_apply then
        local current = recipe.maximum_productivity
        -- A scoped setting is an opt-in upward mutation.  Preserve a larger
        -- cap deliberately supplied by another mod.
        if not scoped or current == nil or current < value then
          if current ~= value then
            recipe.maximum_productivity = value
            changed = changed + 1
          end
        end
      end
    end
  end
  if scoped and value > 3.0 then
    log("[more-infinite-research] Productivity cap self-recycling scope: approved="
      .. tostring(approved) .. " rejected=" .. tostring(rejected) .. ".")
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

local function energy_watts(value)
  if type(value) == "number" then return value end
  if type(value) ~= "string" then return nil end

  local number, unit = string.match(value, "^%s*([%+%-]?%d+%.?%d*)%s*([kKmMgGtT]?)[wW]%s*$")
  if not number then return nil end

  local multiplier_by_unit = {
    [""] = 1,
    k = 1000,
    m = 1000000,
    g = 1000000000,
    t = 1000000000000
  }
  local multiplier = multiplier_by_unit[string.lower(unit or "")]
  if not multiplier then return nil end

  return tonumber(number) * multiplier
end

local function apply_positive_power_floor()
  if effective_settings.get(prototype_limit_settings.positive_power_floor_setting_name) ~= true then
    return 0
  end

  local changed = 0
  for _, group in pairs(data_raw.raw()) do
    if type(group) == "table" then
      for _, prototype in pairs(group) do
        if type(prototype) == "table" and prototype.energy_usage ~= nil and energy_watts(prototype.energy_usage) == 0 then
          prototype.energy_usage = "1W"
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
    pollution = apply_effect_receiver_limit("pollution_limits", "low", selected("pollution")),
    speed = apply_effect_receiver_limit("speed_limits", "high", selected("speed")),
    quality = apply_effect_receiver_limit("quality_limits", "high", selected("quality")),
    positive_power_floor = apply_positive_power_floor()
  }

  if changed.productivity > 0
    or changed.efficiency > 0
    or changed.pollution > 0
    or changed.speed > 0
    or changed.quality > 0
    or changed.positive_power_floor > 0
  then
    log("[more-infinite-research] Applied prototype limits: productivity_recipes="
      .. tostring(changed.productivity)
      .. " efficiency_receivers="
      .. tostring(changed.efficiency)
      .. " pollution_receivers="
      .. tostring(changed.pollution)
      .. " speed_receivers="
      .. tostring(changed.speed)
      .. " quality_receivers="
      .. tostring(changed.quality)
      .. " positive_power_floor_entities="
      .. tostring(changed.positive_power_floor)
      .. ".")
  end

  return changed
end

return P
