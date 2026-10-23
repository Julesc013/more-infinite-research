-- Fixed F200 Bob/Angel material constructor. It binds one captured no-BobTech
-- profile through named routes and owners. It does not discover material
-- families, choose owners, or traverse a foreign research graph.
local cost = require("research.cost")
local DEFINITIONS = require("research.bob_angel_materials")

local M = {}

local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local function fail(message)
  error("MIR5 F200 Bob/Angel material catalogue: " .. message, 3)
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Named bindings qualify this variant only; unrelated foreign technology is
-- not reconstructed or certified here.
function M.is_f200_bob_angel(active_mods)
  return require("compatibility.bob_angel_profile").applies(active_mods)
end

local function entry_name(entry)
  return type(entry) == "table" and (entry.name or entry[1]) or nil
end

local function entry_amount(entry)
  return type(entry) == "table" and (entry.amount or entry[2]) or nil
end

local function entry_catalyst_amount(entry)
  return type(entry) == "table" and entry.catalyst_amount or nil
end

-- A selected recipe has one fully named ordinary form. Return/coproduct,
-- probability, catalyst, and productivity-stat changes are another route.
local function ordinary_rows(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, wanted in ipairs(expected) do
    local row = actual[index]
    if type(row) ~= "table" or (row.type or "item") ~= wanted.type
      or entry_name(row) ~= wanted.name or entry_amount(row) ~= wanted.amount
      or row.amount_min ~= nil or row.amount_max ~= nil
      or (row.probability ~= nil and row.probability ~= 1)
      or (row.independent_probability ~= nil and row.independent_probability ~= 1)
      or (row.shared_probability ~= nil and (type(row.shared_probability) ~= "table"
        or row.shared_probability.min ~= 0 or row.shared_probability.max ~= 1))
      or (entry_catalyst_amount(row) ~= nil and entry_catalyst_amount(row) ~= 0)
      or (row.ignored_by_productivity ~= nil and row.ignored_by_productivity ~= 0)
      or (row.extra_count_fraction ~= nil and row.extra_count_fraction ~= 0) then
      return false
    end
  end
  return true
end

local function maximum_productivity_matches(actual, expected)
  if expected == "omitted" then return actual == nil end
  -- F200 named routes can only bind the captured three-fold ceiling.  Do not
  -- accept an arbitrary foreign cap as though it described the same route.
  return expected == 3 and actual == 3
end

local function names_match(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, name in ipairs(expected) do
    if actual[index] ~= name then return false end
  end
  return true
end

local function route_owner_is_exact(owner, route)
  if type(owner) ~= "table" or owner.enabled == false
    or not names_match(owner.prerequisites or {}, route.owner_prerequisites)
    or not ordinary_rows(type(owner.unit) == "table" and owner.unit.ingredients or nil, route.owner_science) then
    return false
  end

  local unlock_count = 0
  for _, effect in ipairs(owner.effects or {}) do
    if effect.recipe == route.recipe then
      if effect.type == "unlock-recipe" then
        unlock_count = unlock_count + 1
      else
        return false
      end
    end
  end
  return unlock_count == 1
end

local function validate_raw(raw, definition)
  if type(raw) ~= "table" or type(raw.item) ~= "table"
    or type(raw.recipe) ~= "table" or type(raw.technology) ~= "table" then
    fail("named F200 Bob/Angel raw prototypes are unavailable")
  end

  local item = raw.item[definition.item]
  if type(item) ~= "table" or item.icon ~= definition.icon or item.icon_size ~= definition.icon_size then
    fail(definition.item .. " presentation changed")
  end

  for _, route in ipairs(definition.routes) do
    local recipe = raw.recipe[route.recipe]
    if type(recipe) ~= "table" or recipe.enabled ~= false or recipe.hidden == true
      or recipe.allow_productivity ~= true
      or not maximum_productivity_matches(recipe.maximum_productivity, route.maximum_productivity)
      or not ordinary_rows(recipe.ingredients, route.ingredients)
      or not ordinary_rows(recipe.results, route.results) then
      fail(route.recipe .. " changed")
    end
    if not route_owner_is_exact(raw.technology[route.owner], route) then
      fail(route.owner .. " no longer owns " .. route.recipe)
    end
  end
end

local function stream_for(values, definition)
  local stream = type(values) == "table" and type(values.streams) == "table"
    and values.streams[definition.key] or nil
  if type(stream) ~= "table" or type(stream.enabled) ~= "boolean"
      or not finite(stream.base_cost) or stream.base_cost < 1
      or not finite(stream.linear_increment) or stream.linear_increment < 0
      or not finite(stream.growth_factor) or stream.growth_factor < 1
      or not finite(stream.research_time) or stream.research_time <= 0
      or not finite(stream.effect_percent) or stream.effect_percent <= 0 then
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
  for index, pack in ipairs(science) do output[index] = {pack, 1} end
  return output
end

local function effects(routes, effect_percent)
  local output = {}
  for index, route in ipairs(routes) do
    output[index] = {
      type = "change-recipe-productivity",
      recipe = route.recipe,
      change = effect_percent / 100,
    }
  end
  return output
end

-- The finite early stage keeps its configured exponential stream. The
-- published continuation anchors at the early stage's level-four cost and
-- then adds the configured base cost per later level, exactly as the captured
-- F200 reference does. This remains a five-family local rule, not a generic
-- progression planner.
local function material_continuation_cost(stream, stage)
  local first = (stream.base_cost + 3 * stream.linear_increment) * (stream.growth_factor ^ 3)
  if not finite(first) then
    fail("material continuation cost is not finite")
  end
  return cost.continuation({
    base_cost = first,
    linear_increment = stream.base_cost,
    growth_factor = 1,
  }, stage.first_level, stage.predecessor_count, stage.previous_count)
end

local function technology(definition, stage, stream)
  local output = {
    type = "technology",
    name = stage.id,
    icons = {
      {icon = definition.icon, icon_size = definition.icon_size},
      {icon = OVERLAY, icon_size = 128, scale = 0.5, shift = {50, 50}, floating = true},
    },
    localised_name = {"", {"description.productivity-bonus"}, ": ", {"item-name." .. definition.item}},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    level = stage.first_level or 1,
    upgrade = true,
    max_level = stage.max_level,
    order = stage.order,
    prerequisites = copy_names(stage.prerequisites),
    effects = effects(definition.routes, stream.effect_percent),
    unit = {
      count_formula = stage.first_level
        and material_continuation_cost(stream, stage)
        or cost.cost(stream.base_cost, stream.linear_increment, stream.growth_factor),
      time = stream.research_time,
      ingredients = ingredients(stage.science),
    },
  }
  if stream.enabled == false then output.enabled = false end
  return output
end

-- All named input bindings and resolved settings are checked before the first
-- fresh output table is returned. The shared Generator owns the one write.
function M.technologies(values, raw, active_mods)
  if not M.is_f200_bob_angel(active_mods) then return {} end

  local streams = {}
  for index, definition in ipairs(DEFINITIONS) do
    validate_raw(raw, definition)
    streams[index] = stream_for(values, definition)
  end

  local output = {}
  for index, definition in ipairs(DEFINITIONS) do
    local stream = streams[index]
    output[#output + 1] = technology(definition, definition.early, stream)
    output[#output + 1] = technology(definition, definition.continuation, stream)
  end
  return output
end

return M
