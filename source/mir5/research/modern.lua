-- Construction for the explicit F210 modern catalogue. The compatibility
-- module selects its bounded definitions; this module only builds fresh native
-- tables and checks the named three-recipe Space Age patch boundary.
local catalogue = require("compatibility.modern_catalogue")
local productivity = require("research.productivity")

local M = {}

local OVERLAY_SIZE = 128

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR modern research definition contains a cycle", 3) end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function number_text(value)
  assert(finite(value) and value >= 0, "MIR invalid modern research number")
  if value == math.floor(value) then return tostring(math.floor(value)) end
  return string.format("%.15g", value)
end

local function legacy_six(value)
  assert(finite(value) and value >= 0, "MIR invalid continuation cost number")
  local text = string.format("%.6g", value)
  local number = tonumber(text)
  assert(number ~= nil, "MIR invalid continuation formula number")
  return number, text
end

local function append_unique(out, seen, names)
  for index = 1, #names do
    local name = names[index]
    if not seen[name] then out[#out + 1], seen[name] = name, true end
  end
end

local function generated_prerequisites(definition)
  local out, seen = {}, {}
  append_unique(out, seen, catalogue.science_names(definition.science))
  append_unique(out, seen, definition.prerequisites or {})
  return out
end

local function continuation_prerequisites(definition)
  local out, seen = {}, {}
  append_unique(out, seen, definition.prerequisites or {})
  append_unique(out, seen, catalogue.science_names(definition.science))
  return out
end

local function icons(definition)
  return {
    {icon = definition.icon, icon_size = definition.icon_size or 256},
    {icon = definition.overlay, icon_size = OVERLAY_SIZE, scale = 0.5, shift = {50, 50}, floating = true}
  }
end

local function normal_effects(definition, values)
  local out = {}
  for index = 1, #definition.effects do
    local effect = definition.effects[index]
    if definition.kind == "productivity" then
      out[index] = {type = "change-recipe-productivity", recipe = effect.recipe,
        change = values.effect_percent * effect.scale / 100}
    else
      local result = {type = effect.type, modifier = values.effect_percent * effect.scale}
      if effect.ammo_category then result.ammo_category = effect.ammo_category end
      if not effect.raw then result.modifier = result.modifier / 100 end
      out[index] = result
    end
  end
  return out
end

local function localized(value)
  if type(value) == "string" then return {value} end
  return copy(value)
end

local function require_stream(values, family)
  local stream = values and values.streams and values.streams[family]
  if type(stream) ~= "table" then error("MIR modern research has no resolved stream values for " .. family, 3) end
  return stream
end

function M.technology(definition, values)
  local stream = require_stream(values, definition.family)
  local output = {
    type = "technology", name = "recipe-prod-" .. definition.key .. "-1",
    icons = icons(definition), localised_name = copy(definition.localised_name),
    localised_description = copy(definition.localised_description), level = 1,
    upgrade = true, max_level = "infinite", order = definition.order,
    prerequisites = generated_prerequisites(definition), effects = normal_effects(definition, stream),
    unit = {
      count_formula = productivity.cost(stream.base_cost, stream.linear_increment, stream.growth_factor),
      time = stream.research_time, ingredients = catalogue.science_ingredients(definition.science)
    }
  }
  if stream.enabled == false then output.enabled = false end
  return output
end

local function continuation_formula(definition, stream)
  local defaults, inheritance = definition.defaults, definition.inheritance
  local growth = stream.growth_factor
  if growth == 0 then growth = inheritance.last_count / inheritance.previous_count end
  local base = stream.base_cost
  if base == 0 then base = inheritance.last_count / (growth ^ (definition.level - 1)) end
  local legacy_base, base_text = legacy_six(base)
  local legacy_growth, growth_text = legacy_six(growth)
  local first = legacy_base * (legacy_growth ^ (definition.level - 1))
  local first_text = number_text(first)
  local increment = stream.linear_increment
  if legacy_growth == 1 then
    if increment == 0 then return first_text end
    return first_text .. "+" .. number_text(increment) .. "*(L-" .. definition.level .. ")"
  end
  if increment == 0 then return first_text .. "*" .. growth_text .. "^(L-" .. definition.level .. ")" end
  return "(" .. first_text .. "+" .. number_text(increment) .. "*(L-" .. definition.level .. "))*"
    .. growth_text .. "^(L-" .. definition.level .. ")"
end

local function continuation_effects(definition, stream)
  local out = {}
  for index = 1, #definition.effects do
    local authored = definition.effects[index]
    local effect = {type = authored.type, modifier = stream.effect_percent * authored.scale / 100}
    if authored.ammo_category then effect.ammo_category = authored.ammo_category end
    -- Worker storage and the two inserter capacities are absolute values;
    -- their historical startup values are measured in units, not percent.
    if authored.type == "worker-robot-storage" or authored.type == "inserter-stack-size-bonus"
      or authored.type == "bulk-inserter-capacity-bonus" then
      effect.modifier = stream.effect_percent * authored.scale
    end
    out[index] = effect
  end
  return out
end

function M.continuation(definition, values)
  local stream = require_stream(values, definition.family)
  local time = stream.research_time
  if time == 0 then time = definition.inheritance.research_time end
  local output = {
    type = "technology", name = definition.id, icons = icons(definition),
    localised_name = localized(definition.localised_name), localised_description = localized(definition.localised_description),
    level = definition.level, upgrade = true, hidden = false, max_level = "infinite",
    prerequisites = continuation_prerequisites(definition), effects = continuation_effects(definition, stream),
    unit = {count_formula = continuation_formula(definition, stream), time = time,
      ingredients = catalogue.science_ingredients(definition.science)}
  }
  if stream.enabled == false then output.enabled = false end
  return output
end

function M.technologies(selection, values)
  if type(selection) ~= "table" then error("MIR modern selection is required", 2) end
  local out = {}
  for index = 1, #selection.definitions do out[#out + 1] = M.technology(selection.definitions[index], values) end
  for index = 1, #selection.continuations do out[#out + 1] = M.continuation(selection.continuations[index], values) end
  return out
end

function M.preflight_recipe_patches(selection, raw)
  if type(selection) ~= "table" or type(raw) ~= "table" or type(raw.recipe) ~= "table" then
    error("MIR modern recipe patch preflight requires data.raw.recipe", 2)
  end
  for index = 1, #selection.recipe_patches do
    local name = selection.recipe_patches[index]
    local recipe = raw.recipe[name]
    if type(recipe) ~= "table" then error("MIR modern catalogue missing required recipe " .. name, 2) end
  end
end

function M.apply_recipe_patches(selection, raw)
  M.preflight_recipe_patches(selection, raw)
  for index = 1, #selection.recipe_patches do raw.recipe[selection.recipe_patches[index]].allow_productivity = true end
end

return M
