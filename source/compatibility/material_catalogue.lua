-- Three fixed K2SO material technologies. This is a bounded native constructor,
-- not a route, owner, or progression discovery mechanism.
local cost = require("research.cost")
local catalogue = require("compatibility.modern_catalogue")

local M = {}

local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local DEFINITIONS = require("research.k2_materials")

local function fail(message)
  error("MIR5 K2SO material catalogue: " .. message, 3)
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Compare only the four named ordinary routes. Additional return/catalyst
-- outputs are not admitted by sharing a material's name.
local function ordinary_rows(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, wanted in ipairs(expected) do
    local row = actual[index]
    if type(row) ~= "table" or (row.type or "item") ~= wanted.type
      or row.name ~= wanted.name or row.amount ~= wanted.amount
      or row.amount_min ~= nil or row.amount_max ~= nil
      or (row.probability ~= nil and row.probability ~= 1)
      or (row.independent_probability ~= nil and row.independent_probability ~= 1)
      or (row.shared_probability ~= nil and (type(row.shared_probability) ~= "table"
        or row.shared_probability.min ~= 0 or row.shared_probability.max ~= 1))
      or (row.ignored_by_productivity ~= nil and row.ignored_by_productivity ~= 0)
      or (row.extra_count_fraction ~= nil and row.extra_count_fraction ~= 0) then return false end
  end
  return true
end

local function validate_raw(raw, definition)
  if type(raw) ~= "table" or type(raw.recipe) ~= "table" or type(raw.technology) ~= "table" then
    fail("named K2SO raw prototypes are unavailable")
  end
  for _, route in ipairs(definition.routes) do
    local recipe = raw.recipe[route.recipe]
    if type(recipe) ~= "table" or recipe.enabled ~= false or recipe.allow_productivity ~= true
      or not ordinary_rows(recipe.ingredients, route.ingredients)
      or not ordinary_rows(recipe.results, route.results) then fail(route.recipe .. " changed") end
    local owner = raw.technology[route.owner]
    local unlock = false
    for _, effect in ipairs(type(owner) == "table" and owner.effects or {}) do
      if effect.recipe == route.recipe then
        if effect.type == "unlock-recipe" then unlock = true end
        if effect.type == "change-recipe-productivity" then
          fail(route.owner .. " already supplies productivity for " .. route.recipe)
        end
      end
    end
    if not unlock then fail(route.owner .. " no longer owns " .. route.recipe) end
    -- The emitted research depends on this owner itself. Foreign changes to
    -- that owner's prerequisites therefore remain native gates, not a reason
    -- to reconstruct or certify its transitive researchability.
  end
end

local function stream_for(values, definition)
  local stream = type(values) == "table" and type(values.streams) == "table"
    and values.streams[definition.key] or nil
  if type(stream) ~= "table" or type(stream.enabled) ~= "boolean"
      or not finite(stream.base_cost) or not finite(stream.linear_increment)
      or not finite(stream.growth_factor)
      or not finite(stream.research_time) or not finite(stream.effect_percent) then
    fail(definition.key .. " resolved settings are invalid")
  end
  return stream
end

local function copy_names(names)
  local output = {}
  for index, name in ipairs(names) do output[index] = name end
  return output
end

local function ingredients(science)
  local output = {}
  for index, science_pack in ipairs(science) do output[index] = {science_pack, 1} end
  return output
end

local function effects(routes, effect_percent)
  local output = {}
  for index, route in ipairs(routes) do
    output[index] = {type = "change-recipe-productivity", recipe = route.recipe, change = effect_percent / 100}
  end
  return output
end

local function technology(definition, stream)
  local output = {
    type = "technology",
    name = definition.name,
    icons = {
      {icon = definition.icon, icon_size = 64},
      {icon = OVERLAY, icon_size = 128, scale = 0.5, shift = {50, 50}, floating = true},
    },
    localised_name = {"", {"description.productivity-bonus"}, ": ", {"item-name." .. definition.item}},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    level = 1,
    upgrade = true,
    max_level = 3,
    order = definition.order,
    prerequisites = copy_names(definition.prerequisites),
    effects = effects(definition.routes, stream.effect_percent),
    unit = {
      count_formula = cost.cost(stream.base_cost, stream.linear_increment, stream.growth_factor),
      time = stream.research_time,
      ingredients = ingredients(definition.science),
    },
  }
  if stream.enabled == false then output.enabled = false end
  return output
end

function M.technologies(values, raw, active_mods)
  if not catalogue.is_k2so(active_mods) then
    return {}
  end

  local streams = {}
  for index, definition in ipairs(DEFINITIONS) do
    validate_raw(raw, definition)
    streams[index] = stream_for(values, definition)
  end

  local output = {}
  for index, definition in ipairs(DEFINITIONS) do output[index] = technology(definition, streams[index]) end
  return output
end

return M
