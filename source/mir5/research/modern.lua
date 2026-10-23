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

local function imersite_effect(stream)
  return {type = "change-recipe-productivity", recipe = "kr-imersite-powder", change = stream.effect_percent / 100}
end

local function imersite_continuation_formula(stream, first_level)
  local anchor = (stream.base_cost + (first_level - 1) * stream.linear_increment) * (stream.growth_factor ^ (first_level - 1))
  local head = number_text(anchor)
  if stream.base_cost == 0 then return head end
  return head .. "+" .. number_text(stream.base_cost) .. "*(L-" .. first_level .. ")"
end

-- K2SO's published Imersite stream has a finite public stage, an independent
-- late formula, and two hidden state carriers. It is a named historical shape,
-- not a generic finite-stage engine.
local function k2_imersite_technologies(values)
  local contract = require("research.k2_imersite")
  local stream = require_stream(values, contract.stream)
  local early_science = "science_automation_logistic_chemical_production"
  local continuation_science = "science_production_space"
  local effect = imersite_effect(stream)
  local early = {
    type = "technology", name = contract.early.id, icons = {
      {icon = "__Krastorio2Assets__/icons/items/imersite-powder.png", icon_size = 64},
      {icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png", icon_size = OVERLAY_SIZE,
        scale = 0.5, shift = {50, 50}, floating = true},
    }, localised_name = {"", {"description.productivity-bonus"}, ": ", {"item-name.kr-imersite-powder"}},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    level = contract.early.first_level, upgrade = true, max_level = contract.early.last_level, order = contract.early.order,
    prerequisites = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "kr-quarry-minerals-extraction"},
    effects = {effect}, unit = {count_formula = productivity.cost(stream.base_cost, stream.linear_increment, stream.growth_factor),
      time = stream.research_time, ingredients = catalogue.science_ingredients(early_science)},
  }
  local continuation = {
    type = "technology", name = contract.continuation.id, icons = icons({icon = "__Krastorio2Assets__/icons/items/imersite-powder.png", icon_size = 64,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"}),
    localised_name = {"", {"description.productivity-bonus"}, ": ", {"item-name.kr-imersite-powder"}},
    localised_description = {"", {"technology-description.more-infinite-research.recipe_productivity"}, "\n",
      {"mod-setting-name.ips-max-level-stream", {"", {"description.productivity-bonus"}, ": ", {"item-name.kr-imersite-powder"}}}, ": ", "150"},
    level = contract.continuation.first_level, upgrade = true, max_level = "infinite", order = contract.continuation.order,
    show_levels_info = false, visible_when_disabled = true,
    prerequisites = {"kr-quarry-minerals-extraction", "production-science-pack", contract.early.id, "space-science-pack"},
    effects = {imersite_effect(stream)}, unit = {count_formula = imersite_continuation_formula(stream, contract.continuation.first_level),
      time = stream.research_time, ingredients = catalogue.science_ingredients(continuation_science)},
  }
  if stream.enabled == false then early.enabled, continuation.enabled = false, false end
  local carriers = {}
  for index, carrier in ipairs(contract.carriers) do
    local stage, science, formula = carrier.kind == "early" and contract.early or contract.continuation,
      carrier.kind == "early" and early_science or continuation_science,
      carrier.kind == "early" and productivity.cost(stream.base_cost, stream.linear_increment, stream.growth_factor)
        or imersite_continuation_formula(stream, contract.continuation.first_level)
    carriers[index] = {
      type = "technology", name = carrier.id, icon = "__base__/graphics/technology/automation.png", icon_size = 256,
      localised_name = {"technology-name.more-infinite-research.recipe_productivity"},
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      level = stage.first_level, upgrade = false, hidden = true, enabled = true, max_level = "infinite",
      order = "zz[mir-migration-state]", prerequisites = {}, effects = {imersite_effect(stream)},
      unit = {count_formula = formula, time = stream.research_time, ingredients = catalogue.science_ingredients(science)},
    }
  end
  return {early, continuation, carriers[1], carriers[2]}
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
  if selection.k2_imersite then
    local staged = k2_imersite_technologies(values)
    for index = 1, #staged do out[#out + 1] = staged[index] end
  end
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
