-- Independent opt-in prototype overrides. Effective settings are supplied by
-- the caller; no Generator, runtime or historical production imports.
local M = {}
local target = require("platform.target")
local receivers = {"assembling-machine", "furnace", "rocket-silo", "lab", "mining-drill", "agricultural-tower"}
local limits = {
  {"efficiency", "consumption_limits", "low", -0.8},
  {"pollution", "pollution_limits", "low", -0.8},
  {"speed-floor", "speed_limits", "low", -0.8},
  {"speed", "speed_limits", "high", -0.8},
  {"quality", "quality_limits", "high", 0}
}

local function selected(value)
  if type(value) == "number" then
    if value == value and value > -math.huge and value < math.huge then return value / 100 end
    return nil
  end
  if type(value) ~= "string" or value == "engine-default" then return nil end
  local prefix, number = value:match("^(%a+)%-(%d[%d%-]*)$")
  if prefix ~= "saving" and prefix ~= "bonus" and prefix ~= "percent" then return nil end
  if prefix == "saving" and number == "999" then return -0.999 end
  if prefix == "saving" and number == "9999" then return -0.9999 end
  number = number and tonumber((number:gsub("%-", ".")))
  if number then return (prefix == "saving" and -1 or 1) * number / 100 end
end

local function clone(value)
  if type(value) ~= "table" then return value end
  local copies, pending = {[value]={}}, {value}
  local function detached(item)
    if type(item) ~= "table" then return item end
    if copies[item] == nil then
      copies[item] = {}
      pending[#pending + 1] = item
    end
    return copies[item]
  end
  while #pending > 0 do
    local original = pending[#pending]
    pending[#pending] = nil
    local output = copies[original]
    for key, item in pairs(original) do output[detached(key)] = detached(item) end
  end
  return copies[value]
end

local function variants(recipe)
  if type(recipe.normal) == "table" or type(recipe.expensive) == "table" then
    local out = {}
    if type(recipe.normal) == "table" then out[#out + 1] = recipe.normal end
    if type(recipe.expensive) == "table" then out[#out + 1] = recipe.expensive end
    return out
  end
  return {recipe}
end

local function item(entry)
  return type(entry) == "table" and (entry.type == nil or entry.type == "item") and (entry.name or entry[1])
end

local function recycling(recipes, chance, scope, probability_field)
  if chance == nil then return 0 end
  local changed = 0
  for _, recipe in pairs(recipes) do
    if type(recipe) == "table" and recipe.parameter ~= true and scope.is_recycling(recipe)
      and recipe.hidden == true and recipe.unlock_results == false then
      local valid, rows = true, variants(recipe)
      for _, row in ipairs(rows) do
        if type(row.ingredients) ~= "table" or #row.ingredients ~= 1 or not item(row.ingredients[1]) then valid = false end
      end
      if valid then
        for _, row in ipairs(rows) do
          for _, result in ipairs(row.results or {}) do
            if item(result) and result.shared_probability == nil then
              local current = tonumber(result[probability_field])
              if current == nil then current = tonumber(result.probability) end
              if current == nil then current = 1 end
              local replacement = math.max(0, math.min(1, current * chance / 0.25))
              if math.abs(replacement - current) >= 0.0000001
                or (probability_field ~= "probability" and result.probability ~= nil) then
                result[probability_field] = replacement
                if probability_field ~= "probability" then result.probability = nil end
                changed = changed + 1
              end
            end
          end
        end
      end
    end
  end
  return changed
end

local function zero_power(value)
  if type(value) == "number" then return value == 0 end
  if type(value) ~= "string" then return false end
  local number = value:match("^%s*([%+%-]?%d+%.?%d*)%s*[kKmMgGtT]?[wW]%s*$")
  return tonumber(number) == 0
end

function M.apply(raw, options)
  options = options or {}
  local productivity = selected(options["mir-prototype-productivity-cap"])
  local chance_setting = options["mir-recycling-return-chance"]
  local chance = selected(chance_setting)
  if chance_setting == "match-productivity-cap" then
    chance = math.min(0.25, 1 / (1 + math.max(0, productivity or 3)))
  end
  local facts = {productivity = 0, recycling_products = 0, receivers = 0, positive_power = 0,
    indexed_recipes = 0, unsupported_receiver_limits = 0}
  local scope
  if chance ~= nil or productivity ~= nil then scope = require("overrides.recycling_scope") end
  local recipes = (chance ~= nil or productivity ~= nil) and (raw.recipe or {}) or nil
  if chance ~= nil then facts.recycling_products = recycling(recipes, chance, scope, target.recipe_probability) end
  if productivity ~= nil then
    local threshold = chance == 0 and math.huge or math.max(0, 1 / (chance or 0.25) - 1)
    local classifier
    if options["mir-productivity-cap-self-recycling-only"] == true and productivity > threshold + 0.000001 then
      classifier = scope.build(recipes, threshold, target.productivity_ignores_stats)
      facts.indexed_recipes = classifier.visited
    end
    for name, recipe in pairs(recipes) do
      if type(recipe) == "table" and recipe.parameter ~= true and not scope.is_recycling(recipe) then
        local target = productivity
        if classifier then
          if not classifier.approve(name) then target = threshold end
          local cap = classifier.maximum_safe_productivity(name)
          if cap ~= nil then target = math.min(target, cap) end
        end
        if recipe.maximum_productivity ~= target then recipe.maximum_productivity = target; facts.productivity = facts.productivity + 1 end
      end
    end
  end
  for _, limit in ipairs(limits) do
    local value = selected(options["mir-prototype-" .. limit[1] .. (limit[1] == "speed-floor" and "" or "-cap")])
    if value ~= nil and target.receiver_limits ~= true then
      -- Older native engines have fixed receiver limits. Writing unknown
      -- fields would report a change that the engine cannot apply.
      facts.unsupported_receiver_limits = facts.unsupported_receiver_limits + 1
    elseif value ~= nil then
      for _, kind in ipairs(receivers) do
        for _, prototype in pairs(raw[kind] or {}) do
          if type(prototype) == "table" then
            local old = prototype.effect_receiver or {}
            local range = type(old[limit[2]]) == "table" and old[limit[2]] or nil
            if not range or range[limit[3]] ~= value then
              local receiver = clone(old)
              range = type(receiver[limit[2]]) == "table" and receiver[limit[2]] or {}
              if range.low == nil then range.low = limit[4] end
              if range.high == nil then range.high = 1000 end
              range[limit[3]] = value
              receiver[limit[2]], prototype.effect_receiver = range, receiver
              facts.receivers = facts.receivers + 1
            end
          end
        end
      end
    end
  end
  if options["mir-prototype-positive-power-floor"] == true then
    for _, group in pairs(raw) do
      if type(group) == "table" then
        for _, prototype in pairs(group) do
          if type(prototype) == "table" and zero_power(prototype.energy_usage) then
            prototype.energy_usage = "1W"; facts.positive_power = facts.positive_power + 1
          end
        end
      end
    end
  end
  return facts
end

return M
