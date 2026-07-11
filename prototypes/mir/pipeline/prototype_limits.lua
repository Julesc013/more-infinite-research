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

local function inverse_recycling_productivity_bonus(recycling_chance)
  local chance = tonumber(recycling_chance)
  if chance == nil then chance = 0.25 end
  if chance <= 0 then return math.huge end
  return math.max(0, (1 / chance) - 1)
end

local function apply_recipe_productivity_cap(value, recycling_chance)
  if value == nil then return 0 end

  local changed = 0
  local scoped = effective_settings.get(prototype_limit_settings.self_recycling_scope_setting_name) == true
  local scope_threshold = inverse_recycling_productivity_bonus(recycling_chance)
  local scope_classifier = scoped and value > scope_threshold and cap_scope.build() or nil
  local approved = 0
  local rejected = 0
  for _, recipe in pairs(data_raw.prototypes("recipe")) do
    if type(recipe) == "table" and recipe.parameter ~= true then
      local should_apply = true
      if scope_classifier then
        local safe = scope_classifier.approve(recipe)
        if safe == true then approved = approved + 1 else rejected = rejected + 1 end
        local target = safe == true and value or scope_threshold
        if recipe.maximum_productivity ~= target then
          recipe.maximum_productivity = target
          changed = changed + 1
        end
        should_apply = false
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
  if scope_classifier then
    log("[more-infinite-research] Productivity cap self-recycling scope: approved="
      .. tostring(approved) .. " rejected=" .. tostring(rejected)
      .. " inverse_threshold=" .. tostring(scope_threshold) .. ".")
  end
  return changed
end

local function recipe_categories(recipe)
  if type(recipe.categories) == "table" then return recipe.categories end
  if recipe.category then return {recipe.category} end
  return {"crafting"}
end

local function has_category(recipe, wanted)
  for _, category in ipairs(recipe_categories(recipe)) do
    if category == wanted then return true end
  end
  return false
end

local function recipe_variants(recipe)
  if type(recipe.normal) == "table" or type(recipe.expensive) == "table" then
    local out = {}
    if type(recipe.normal) == "table" then table.insert(out, recipe.normal) end
    if type(recipe.expensive) == "table" then table.insert(out, recipe.expensive) end
    return out
  end
  return {recipe}
end

local function item_name(entry)
  if type(entry) ~= "table" then return nil end
  if entry.type ~= nil and entry.type ~= "item" then return nil end
  return entry.name or entry[1]
end

local function generated_recycling_recipe(recipe)
  if type(recipe) ~= "table" or recipe.parameter == true then return false end
  if not has_category(recipe, "recycling") then return false end
  -- Official and convention-following generated recycler recipes are hidden
  -- and do not unlock their products. This deliberately excludes visible
  -- recycling processes such as scrap recycling.
  if recipe.hidden ~= true or recipe.unlock_results ~= false then return false end
  for _, variant in ipairs(recipe_variants(recipe)) do
    local ingredients = variant.ingredients or {}
    if #ingredients ~= 1 or not item_name(ingredients[1]) then return false end
  end
  return true
end

local function scale_recycling_product(product, multiplier)
  if not item_name(product) then return false end
  if product.shared_probability ~= nil then return false end
  local current = tonumber(product.independent_probability)
  if current == nil then current = tonumber(product.probability) end
  if current == nil then current = 1 end
  local replacement = math.max(0, math.min(1, current * multiplier))
  if math.abs(replacement - current) < 0.0000001 and product.probability == nil then return false end
  product.independent_probability = replacement
  product.probability = nil
  return true
end

local function apply_recycling_return_chance(productivity_cap)
  local raw = effective_settings.get(prototype_limit_settings.recycling_return_setting_name)
  local chance = prototype_limit_settings.recycling_return_value(raw, productivity_cap)
  if chance == nil then return {recipes = 0, products = 0, chance = nil} end

  local multiplier = chance / 0.25
  local recipes_changed = 0
  local products_changed = 0
  for _, recipe in pairs(data_raw.prototypes("recipe")) do
    if generated_recycling_recipe(recipe) then
      local recipe_changed = false
      for _, variant in ipairs(recipe_variants(recipe)) do
        for _, product in ipairs(variant.results or {}) do
          if scale_recycling_product(product, multiplier) then
            products_changed = products_changed + 1
            recipe_changed = true
          end
        end
      end
      if recipe_changed then recipes_changed = recipes_changed + 1 end
    end
  end
  return {recipes = recipes_changed, products = products_changed, chance = chance}
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
  local productivity_cap = selected("productivity")
  local recycling = apply_recycling_return_chance(productivity_cap)
  local changed = {
    recycling = recycling,
    productivity = apply_recipe_productivity_cap(productivity_cap, recycling.chance),
    efficiency = apply_effect_receiver_limit("consumption_limits", "low", selected("efficiency")),
    pollution = apply_effect_receiver_limit("pollution_limits", "low", selected("pollution")),
    speed_floor = apply_effect_receiver_limit("speed_limits", "low", selected("speed_floor")),
    speed = apply_effect_receiver_limit("speed_limits", "high", selected("speed")),
    quality = apply_effect_receiver_limit("quality_limits", "high", selected("quality")),
    positive_power_floor = apply_positive_power_floor()
  }

  if changed.productivity > 0
    or changed.recycling.recipes > 0
    or changed.efficiency > 0
    or changed.pollution > 0
    or changed.speed_floor > 0
    or changed.speed > 0
    or changed.quality > 0
    or changed.positive_power_floor > 0
  then
    log("[more-infinite-research] Applied prototype limits: productivity_recipes="
      .. tostring(changed.productivity)
      .. " recycling_recipes="
      .. tostring(changed.recycling.recipes)
      .. " recycling_products="
      .. tostring(changed.recycling.products)
      .. " recycling_return_chance="
      .. tostring(changed.recycling.chance)
      .. " efficiency_receivers="
      .. tostring(changed.efficiency)
      .. " pollution_receivers="
      .. tostring(changed.pollution)
      .. " speed_floor_receivers="
      .. tostring(changed.speed_floor)
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
