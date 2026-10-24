-- Fixed F200 Py Coal constructor.  It binds the named log recipe and its
-- unlock owner before returning detached stages; it does not discover Py
-- forestry routes or infer a material progression graph.
local cost = require("research.cost")
local DEFINITIONS = require("research.py_materials")
local profile = require("compatibility.py_profile")

local M = {}
local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local function fail(message) error("MIR5 F200 Py material catalogue: " .. message, 3) end
local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function entry_name(row) return type(row) == "table" and (row.name or row[1]) or nil end
local function entry_amount(row) return type(row) == "table" and (row.amount or row[2]) or nil end

local function ordinary(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, wanted in ipairs(expected) do
    local row = actual[index]
    if type(row) ~= "table" or (row.type or "item") ~= wanted.type
      or entry_name(row) ~= wanted.name or entry_amount(row) ~= wanted.amount
      or row.amount_min ~= nil or row.amount_max ~= nil
      or (row.probability ~= nil and row.probability ~= 1)
      or (row.independent_probability ~= nil and row.independent_probability ~= 1)
      or (row.catalyst_amount ~= nil and row.catalyst_amount ~= 0)
      or (row.ignored_by_productivity ~= nil and row.ignored_by_productivity ~= 0)
      or (row.extra_count_fraction ~= nil and row.extra_count_fraction ~= 0) then return false end
  end
  return true
end

local function exact_names(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, name in ipairs(expected) do if actual[index] ~= name then return false end end
  return true
end

local function validate(raw, definition)
  if type(raw) ~= "table" or type(raw.item) ~= "table" or type(raw.recipe) ~= "table"
      or type(raw.technology) ~= "table" then fail("named Py raw prototypes are unavailable") end
  local item = raw.item[definition.item]
  if type(item) ~= "table" or item.icon ~= definition.icon or item.icon_size ~= definition.icon_size then
    fail(definition.item .. " presentation changed")
  end
  for _, route in ipairs(definition.routes) do
    local recipe, owner = raw.recipe[route.recipe], raw.technology[route.owner]
    if type(recipe) ~= "table" or recipe.enabled ~= false or recipe.hidden == true
      or recipe.allow_productivity ~= true or recipe.maximum_productivity ~= route.maximum_productivity
      or not ordinary(recipe.ingredients, route.ingredients) or not ordinary(recipe.results, route.results) then
      fail(route.recipe .. " changed")
    end
    if type(owner) ~= "table" or owner.enabled == false
      or not exact_names(owner.prerequisites or {}, route.owner_prerequisites)
      or not ordinary(owner.unit and owner.unit.ingredients, route.owner_science) then
      fail(route.owner .. " no longer owns " .. route.recipe)
    end
    local count = 0
    for _, effect in ipairs(owner.effects or {}) do
      if effect.recipe == route.recipe then
        if effect.type ~= "unlock-recipe" then fail(route.owner .. " no longer owns " .. route.recipe) end
        count = count + 1
      end
    end
    if count ~= 1 then fail(route.owner .. " no longer owns " .. route.recipe) end
  end
  for _, stage in ipairs({definition.early, definition.continuation}) do
    for _, name in ipairs(stage.prerequisites) do
      if name ~= definition.early.id and raw.technology[name] == nil then fail(stage.id .. " has missing prerequisite " .. name) end
    end
  end
end

local function stream_for(values, definition)
  local stream = type(values) == "table" and type(values.streams) == "table" and values.streams[definition.key] or nil
  if type(stream) ~= "table" or type(stream.enabled) ~= "boolean"
      or not finite(stream.base_cost) or stream.base_cost < 1
      or not finite(stream.linear_increment) or stream.linear_increment < 0
      or not finite(stream.growth_factor) or stream.growth_factor < 1
      or not finite(stream.research_time) or stream.research_time <= 0
      or not finite(stream.effect_percent) or stream.effect_percent <= 0 then fail(definition.key .. " resolved settings are invalid") end
  return stream
end

local function copy_names(names)
  local out = {}
  for index, name in ipairs(names) do out[index] = name end
  return out
end

local function continuation_cost(stream, stage)
  local first = (stream.base_cost + 3 * stream.linear_increment) * (stream.growth_factor ^ 3)
  if not finite(first) then fail("material continuation cost is not finite") end
  return cost.continuation({base_cost=first,linear_increment=stream.base_cost,growth_factor=1},
    stage.first_level, stage.predecessor_count, stage.previous_count)
end

local function technology(definition, stage, stream)
  local ingredients = {}
  for index, pack in ipairs(stage.science) do ingredients[index] = {pack, 1} end
  local output = {
    type="technology", name=stage.id,
    icons={{icon=definition.icon,icon_size=definition.icon_size},
      {icon=OVERLAY,icon_size=128,scale=.5,shift={50,50},floating=true}},
    localised_name={"",{"description.productivity-bonus"},": ",{"item-name." .. definition.item}},
    localised_description={"technology-description.more-infinite-research.recipe_productivity"},
    level=stage.first_level or 1, upgrade=true, max_level=stage.max_level, order=stage.order,
    prerequisites=copy_names(stage.prerequisites),
    effects={{type="change-recipe-productivity",recipe=definition.routes[1].recipe,change=stream.effect_percent / 100}},
    unit={count_formula=stage.first_level and continuation_cost(stream, stage)
      or cost.cost(stream.base_cost, stream.linear_increment, stream.growth_factor),
      time=stream.research_time,ingredients=ingredients},
  }
  if stream.enabled == false then output.enabled = false end
  return output
end

function M.technologies(values, raw, active_mods)
  if not profile.select(active_mods).coal then return {} end
  local streams = {}
  for index, definition in ipairs(DEFINITIONS) do validate(raw, definition); streams[index] = stream_for(values, definition) end
  local out = {}
  for index, definition in ipairs(DEFINITIONS) do
    out[#out + 1] = technology(definition, definition.early, streams[index])
    out[#out + 1] = technology(definition, definition.continuation, streams[index])
  end
  return out
end

return M
