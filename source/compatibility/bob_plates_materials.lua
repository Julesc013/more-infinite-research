-- Explicit F210 individual Bob Plates constructor.  It neither discovers
-- routes nor emits prototypes; it accepts only captured named direct inputs.
local definitions = require("research.bob_plates_materials")
local stages = require("research.material_stages")
local material_routes = require("compatibility.material_routes")
local target = require("platform.target")

local M = {}

local REQUIRED = {"base", "boblibrary", "bobores", "bobplates"}
local OWNERSHIP_CONFLICTS = {"bobelectronics", "bobtech", "angelssmelting"}

local function fail(message) error("MIR5 F210 Bob Plates material catalogue: " .. message, 3) end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function M.select(active_mods)
  if target.id ~= "f210" or target.factorio_version ~= "2.1" or target.minimum_base ~= "2.1.23"
      or type(active_mods) ~= "table" then return nil end
  for _, name in ipairs(REQUIRED) do if active_mods[name] == nil then return nil end end
  for _, name in ipairs(OWNERSHIP_CONFLICTS) do if active_mods[name] ~= nil then return nil end end
  return active_mods["space-age"] ~= nil and "space-age" or "base"
end

function M.applies(active_mods) return M.select(active_mods) ~= nil end

local function exact_entry(actual, expected)
  if type(actual) ~= "table" or type(expected) ~= "table" then return false end
  for key, wanted in pairs(expected) do if actual[key] ~= wanted then return false end end
  return true
end

local function exact_rows(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, wanted in ipairs(expected) do if not exact_entry(actual[index], wanted) then return false end end
  return true
end

local function product_owner_unlocks(raw, route)
  if route.owner == nil then return true end
  local owner = raw.technology[route.owner]
  if type(owner) ~= "table" then return false end
  local count = 0
  for _, effect in ipairs(owner.effects or {}) do
    if effect.recipe == route.recipe then
      if effect.type ~= "unlock-recipe" then return false end
      count = count + 1
    end
  end
  return count == 1
end

local function product_allow_productivity_matches(actual, expected)
  if expected == "default" then return actual == nil or actual == true end
  return actual == expected
end

local function validate_product_route(raw, route)
  local recipe = raw.recipe[route.recipe]
  if type(recipe) ~= "table" or recipe.enabled ~= route.enabled or recipe.hidden == true
      or not product_allow_productivity_matches(recipe.allow_productivity, route.allow_productivity)
      or not (route.maximum_productivity == "omitted" and (recipe.maximum_productivity == nil or recipe.maximum_productivity == 3))
      or not exact_rows(recipe.ingredients, route.ingredients) or not exact_rows(recipe.results, route.results)
      or not product_owner_unlocks(raw, route) then
    fail(route.recipe .. " changed")
  end
end

local function validate_product(raw, definition)
  -- Lithium's published research uses Base's mining-productivity icon rather
  -- than the native lithium item icon.  The item identity is still an exact
  -- consumed route endpoint, but its native presentation is not.
  if type(raw.item[definition.item]) ~= "table" or raw.item[definition.item].type ~= "item" then
    fail(definition.item .. " is unavailable")
  end
  for _, route in ipairs(definition.routes) do validate_product_route(raw, route) end
  for _, prerequisite in ipairs(definition.prerequisites) do
    if raw.technology[prerequisite] == nil then fail(definition.key .. " has missing prerequisite " .. prerequisite) end
  end
end

local function stream_for(values, definition)
  local stream = type(values) == "table" and type(values.streams) == "table" and values.streams[definition.key] or nil
  if type(stream) ~= "table" or type(stream.enabled) ~= "boolean"
      or not finite(stream.base_cost) or stream.base_cost < 1
      or not finite(stream.linear_increment) or stream.linear_increment < 0
      or not finite(stream.growth_factor) or stream.growth_factor < 1
      or not finite(stream.max_level) or stream.max_level < 0 or stream.max_level ~= math.floor(stream.max_level)
      or not finite(stream.research_time) or stream.research_time <= 0
      or not finite(stream.effect_percent) or stream.effect_percent <= 0 then
    fail(definition.key .. " resolved settings are invalid")
  end
  return stream
end

local function continuation_description(definition, stream)
  local useful = math.ceil(definition.productivity_ceiling * 100 / stream.effect_percent)
  local limit = stream.max_level > 0 and math.min(stream.max_level, useful) or useful
  return {"", {"technology-description.more-infinite-research.recipe_productivity"}, "\n",
    {"mod-setting-name.ips-max-level-stream", {"", {"description.productivity-bonus"}, ": ",
      {"item-name." .. definition.item}}}, ": ", tostring(limit)}
end

function M.preflight(raw, active_mods)
  local profile = M.select(active_mods)
  if profile == nil then return nil end
  if type(raw) ~= "table" or type(raw.item) ~= "table" or type(raw.recipe) ~= "table"
      or type(raw.technology) ~= "table" then
    fail("named F210 Bob Plates raw prototypes are unavailable")
  end
  for _, definition in ipairs(definitions.material_definitions(profile)) do material_routes.preflight(raw, definition, fail) end
  for _, definition in ipairs(definitions.product_definitions(profile)) do validate_product(raw, definition) end
  return profile
end

function M.product_definitions(active_mods)
  local profile = M.select(active_mods)
  return profile and definitions.product_definitions(profile) or {}
end

function M.technologies(values, raw, active_mods)
  local profile = M.preflight(raw, active_mods)
  if profile == nil then return {} end
  local output = {}
  for _, definition in ipairs(definitions.material_definitions(profile)) do
    local stream = stream_for(values, definition)
    output[#output + 1] = stages.technology(definition, definition.early, stream, fail)
    local continuation = stages.technology(definition, definition.continuation, stream, fail)
    continuation.localised_description = continuation_description(definition, stream)
    output[#output + 1] = continuation
  end
  return output
end

return M
