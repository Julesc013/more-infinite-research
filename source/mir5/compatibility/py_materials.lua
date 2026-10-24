-- Fixed F200 Py Coal constructor.  It binds the named log recipe and its
-- unlock owner before returning detached stages; it does not discover Py
-- forestry routes or infer a material progression graph.
local stages = require("research.material_stages")
local DEFINITIONS = require("research.py_materials")
local profile = require("compatibility.py_profile")

local M = {}

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


function M.technologies(values, raw, active_mods)
  if not profile.select(active_mods).coal then return {} end
  local streams = {}
  for index, definition in ipairs(DEFINITIONS) do validate(raw, definition); streams[index] = stream_for(values, definition) end
  local out = {}
  for index, definition in ipairs(DEFINITIONS) do
    out[#out + 1] = stages.technology(definition, definition.early, streams[index], fail)
    out[#out + 1] = stages.technology(definition, definition.continuation, streams[index], fail)
  end
  return out
end

return M
