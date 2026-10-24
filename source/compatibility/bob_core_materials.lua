-- Exact F210 no-Angel Bob Core material constructor.  It validates the seven
-- named routes and declared prerequisite references before returning fourteen
-- detached MIR technologies.  It does not search recipe, owner, or science
-- graphs.
local stages = require("research.material_stages")
local DEFINITIONS = require("research.bob_core_materials")
local target = require("platform.target")

local M = {}

local function fail(message)
  error("MIR5 F210 Bob Core material catalogue: " .. message, 3)
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function M.applies(active_mods)
  return require("compatibility.bob_core_profile").applies(active_mods)
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

local function maximum_productivity_matches(recipe, expected)
  -- Exact F210 native default: omission and explicit 3 have the same ceiling.
  if expected == "omitted" then return recipe.maximum_productivity == nil or recipe.maximum_productivity == 3 end
  return recipe.maximum_productivity == expected
end

local function enabled_matches(recipe, expected)
  -- An omitted native enabled flag means true. Preserve that equivalence;
  -- the five named unlock routes still require an explicit false flag.
  if expected == nil then return recipe.enabled == nil or recipe.enabled == true end
  return recipe.enabled == expected
end

local function named_owner_unlocks(raw, route)
  if route.owner == nil then return true end
  local owner = raw.technology[route.owner]
  if type(owner) ~= "table" then return false end
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
    fail("named F210 Bob Core raw prototypes are unavailable")
  end
  local item = raw.item[definition.item]
  if type(item) ~= "table" or item.icon ~= definition.icon
      or (item.icon_size or 64) ~= definition.icon_size then
    fail(definition.item .. " presentation changed")
  end
  for _, route in ipairs(definition.routes) do
    local recipe = raw.recipe[route.recipe]
    if type(recipe) ~= "table" or not enabled_matches(recipe, route.enabled) or recipe.hidden == true
        or recipe.allow_productivity ~= true
        or not maximum_productivity_matches(recipe, route.maximum_productivity)
        or not ordinary_rows(recipe.ingredients, route.ingredients)
        or not ordinary_rows(recipe.results, route.results, true) then
      fail(route.recipe .. " changed")
    end
    if not named_owner_unlocks(raw, route) then
      fail((route.owner or "named owner") .. " no longer owns " .. route.recipe)
    end
  end
  for _, stage in ipairs({definition.early, definition.continuation}) do
    for _, prerequisite in ipairs(stage.prerequisites) do
      if prerequisite ~= definition.early.id and raw.technology[prerequisite] == nil then
        fail(stage.id .. " has missing prerequisite " .. prerequisite)
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
      or not finite(stream.max_level) or stream.max_level < 0 or stream.max_level ~= math.floor(stream.max_level)
      or not finite(stream.research_time) or stream.research_time <= 0
      or not finite(stream.effect_percent) or stream.effect_percent <= 0 then
    fail(definition.key .. " resolved settings are invalid")
  end
  return stream
end

local function continuation_description(definition, stream)
  -- The captured default tail displayed 150. At the default 2 percent and
  -- the declared threefold productivity ceiling, that is also the useful
  -- level bound selected by runtime.lifecycle when max_level is 0. The
  -- runtime later reads the effective named RecipePrototype cap after any
  -- prototype policy, so this data-stage caption is not a second cap policy.
  local useful = math.ceil(definition.productivity_ceiling * 100 / stream.effect_percent)
  local limit = stream.max_level > 0 and math.min(stream.max_level, useful) or useful
  return {"", {"technology-description.more-infinite-research.recipe_productivity"}, "\n",
    {"mod-setting-name.ips-max-level-stream", {"", {"description.productivity-bonus"}, ": ",
      {"item-name." .. definition.item}}}, ": ", tostring(limit)}
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
    local continuation = stages.technology(definition, definition.continuation, stream, fail)
    continuation.localised_description = continuation_description(definition, stream)
    output[#output + 1] = continuation
  end
  return output
end

return M
