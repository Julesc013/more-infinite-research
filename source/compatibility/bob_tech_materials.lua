-- Exact F210 BobTech material constructor.  It validates only five named
-- published rows and their direct owner bindings before returning fresh MIR
-- technologies.  It neither discovers alternative routes nor inspects a
-- foreign technology graph.
local stages = require("research.material_stages")
local DEFINITIONS = require("research.bob_tech_materials")
local target = require("platform.target")

local M = {}

local function fail(message)
  error("MIR5 F210 BobTech material catalogue: " .. message, 3)
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function M.applies(active_mods)
  return require("compatibility.bob_tech_profile").applies(active_mods)
end

local function entry_name(entry)
  return type(entry) == "table" and (entry.name or entry[1]) or nil
end

local function entry_amount(entry)
  return type(entry) == "table" and (entry.amount or entry[2]) or nil
end

local function ordinary_rows(actual, expected, product)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, wanted in ipairs(expected) do
    local row = actual[index]
    if type(row) ~= "table" then return false end
    local ignored = row.ignored_by_productivity
    if product and ignored == nil and target.productivity_ignores_stats == true then
      ignored = row.ignored_by_stats
    end
    if (row.type or "item") ~= wanted.type
        or entry_name(row) ~= wanted.name or entry_amount(row) ~= wanted.amount
        or row.amount_min ~= nil or row.amount_max ~= nil
        or (row.probability ~= nil and row.probability ~= 1)
        or (row.independent_probability ~= nil and row.independent_probability ~= 1)
        or (row.shared_probability ~= nil and (type(row.shared_probability) ~= "table"
          or row.shared_probability.min ~= 0 or row.shared_probability.max ~= 1))
        or (row.catalyst_amount ~= nil and row.catalyst_amount ~= 0)
        or (ignored ~= nil and ignored ~= 0)
        or (row.extra_count_fraction ~= nil and row.extra_count_fraction ~= 0) then
      return false
    end
  end
  return true
end

local function exact_names(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, name in ipairs(expected) do if actual[index] ~= name then return false end end
  return true
end

local function maximum_productivity_matches(actual, expected)
  -- F210's omitted RecipePrototype ceiling is 3; native dumps materialize it.
  -- Compare that effective value without mutating the upstream recipe.
  if actual == nil then actual = 3 end
  return actual == expected
end

local function owner_matches(owner, route)
  if type(owner) ~= "table" or owner.enabled == false
      or not exact_names(owner.prerequisites or {}, route.owner_prerequisites)
      or not ordinary_rows(type(owner.unit) == "table" and owner.unit.ingredients or nil, route.owner_science) then
    return false
  end
  local matches = 0
  for _, effect in ipairs(owner.effects or {}) do
    if effect.recipe == route.recipe then
      if effect.type ~= "unlock-recipe" then return false end
      matches = matches + 1
    end
  end
  return matches == 1
end

local function validate_raw(raw, definition)
  if type(raw) ~= "table" or type(raw.item) ~= "table" or type(raw.recipe) ~= "table"
      or type(raw.technology) ~= "table" then
    fail("named F210 BobTech raw prototypes are unavailable")
  end
  local item = raw.item[definition.item]
  if type(item) ~= "table" or item.icon ~= definition.icon or item.icon_size ~= definition.icon_size then
    fail(definition.item .. " presentation changed")
  end
  for _, route in ipairs(definition.routes) do
    local recipe = raw.recipe[route.recipe]
    if type(recipe) ~= "table" then fail(route.recipe .. " changed: recipe is absent") end
    if not maximum_productivity_matches(recipe.maximum_productivity, route.maximum_productivity) then
      fail(route.recipe .. " changed: maximum_productivity is " .. tostring(recipe.maximum_productivity)
        .. ", expected effective " .. tostring(route.maximum_productivity))
    end
    if recipe.enabled ~= false or recipe.hidden == true or recipe.allow_productivity ~= true then
      fail(route.recipe .. " changed: availability or productivity flags")
    end
    if not ordinary_rows(recipe.ingredients, route.ingredients) then
      fail(route.recipe .. " changed: ingredients")
    end
    if not ordinary_rows(recipe.results, route.results, true) then
      fail(route.recipe .. " changed: results")
    end
    if not owner_matches(raw.technology[route.owner], route) then
      fail(route.owner .. " no longer owns " .. route.recipe)
    end
  end
  for _, stage in ipairs({definition.early, definition.continuation}) do
    if stage then
      for _, prerequisite in ipairs(stage.prerequisites) do
        if prerequisite ~= definition.early.id and raw.technology[prerequisite] == nil then
          fail(stage.id .. " has missing prerequisite " .. prerequisite)
        end
      end
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


function M.technologies(values, raw, active_mods)
  if not M.applies(active_mods) then return {} end
  local streams = {}
  for index, definition in ipairs(DEFINITIONS) do
    validate_raw(raw, definition)
    streams[index] = stream_for(values, definition)
  end
  local output = {}
  for index, definition in ipairs(DEFINITIONS) do
    local stream = streams[index]
    output[#output + 1] = stages.technology(definition, definition.early, stream, fail)
    if definition.continuation then
      output[#output + 1] = stages.technology(definition, definition.continuation, stream, fail)
    end
  end
  return output
end

return M
