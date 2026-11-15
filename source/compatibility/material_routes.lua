-- Direct material-route preflight shared by named F210 adapters.
-- Reads only the supplied item, recipes, owners and stage prerequisite names;
-- it neither selects a profile nor scans/traverses prototypes or writes them.
local target = require("platform.target")
local ordinary_rows = require("compatibility.ordinary_rows")
local M = {}

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
        or not ordinary_rows.matches(recipe.ingredients, route.ingredients)
        or not ordinary_rows.matches(recipe.results, route.results, target.productivity_ignores_stats == true) then
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

-- The selected family either keeps its full future effect vector or retains
-- that entire vector unavailable. A partial vector needs explicit earned-state
-- preservation; do not silently drop an unsafe effect or useful safe research.
function M.return_reason(raw, definition, context, fail)
  local returns = require("compatibility.material_returns")
  local count, first = 0, nil
  for _, route in ipairs(definition.routes) do
    local recipe = raw.recipe[route.recipe]
    local reason = returns.find_return(raw, recipe.results, recipe.ingredients, context, route.recipe)
    if reason then count, first = count + 1, first or reason end
  end
  if count > 0 and count < #definition.routes then
    fail("mixed material return paths for " .. definition.key .. ": " .. first)
  end
  return first
end

return M
