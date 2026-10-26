-- Direct material-route preflight shared by named F210 adapters.
-- Reads only the supplied item, recipes, owners and stage prerequisite names;
-- it neither selects a profile nor scans/traverses prototypes or writes them.
local target = require("platform.target")
local M = {}

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

function M.preflight(raw, definition, fail)
  if type(raw) ~= "table" or type(raw.item) ~= "table" or type(raw.recipe) ~= "table"
      or type(raw.technology) ~= "table" then
    fail("named material raw prototypes are unavailable")
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

return M
