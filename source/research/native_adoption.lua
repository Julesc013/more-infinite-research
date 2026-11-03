-- Only additional recipes MIR appended or explicitly tuned on its five
-- declared native owners cross the data/control boundary. This is not
-- saved history, an inferred owner list, or permission to accept extra effects.
local M = {prototype_name="more-infinite-research-native-adoptions"}

local function fail(message) error("MIR native adoption data: " .. message, 3) end
local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function M.prototype()
  return {type="mod-data", name=M.prototype_name, data={schema=1, owners={}}}
end

function M.plan(raw, targets)
  local owners = {}
  for _, row in ipairs(targets or {}) do
    if row.extended then
      local recipes = {}
      for index, name in ipairs(row.admitted_recipes or {}) do recipes[index] = name end
      if #recipes == 0 or not finite(row.effect_change) then fail("missing admitted effects") end
      owners[row.definition.id] = {recipes=recipes, effect_change=row.effect_change,
        configured_change=row.configured_effect and row.effect_change or false}
    end
  end
  if next(owners) == nil then return nil end
  local prototype = raw["mod-data"] and raw["mod-data"][M.prototype_name]
  if type(prototype) ~= "table" or prototype.type ~= "mod-data" or prototype.name ~= M.prototype_name
      or type(prototype.data) ~= "table" or prototype.data.schema ~= 1
      or type(prototype.data.owners) ~= "table" or next(prototype.data.owners) ~= nil then
    fail("missing or changed private prototype")
  end
  for key in pairs(prototype.data) do
    if key ~= "schema" and key ~= "owners" then fail("changed private prototype data") end
  end
  return {prototype=prototype, owners=owners}
end

function M.apply(patch)
  if patch then patch.prototype.data.owners = patch.owners end
end

-- Called once by the control adapter with the one named LuaModData.data and
-- the authored native definitions. No force or recipe collection is inspected.
function M.read(value, definitions)
  if type(value) ~= "table" or value.schema ~= 1 or type(value.owners) ~= "table" then
    fail("invalid control data")
  end
  for key in pairs(value) do if key ~= "schema" and key ~= "owners" then fail("unknown control field") end end
  local allowed, out = {}, {}
  for _, definition in ipairs(definitions) do allowed[definition.id] = true end
  for name, row in pairs(value.owners) do
    if allowed[name] ~= true or type(row) ~= "table" or not finite(row.effect_change)
        or row.configured_change ~= false and not finite(row.configured_change)
        or type(row.recipes) ~= "table" or #row.recipes == 0 then
      fail("invalid declared owner")
    end
    for key in pairs(row) do
      if key ~= "recipes" and key ~= "effect_change" and key ~= "configured_change" then
        fail("unknown owner field")
      end
    end
    local recipes, seen, count = {}, {}, 0
    for index, recipe in pairs(row.recipes) do
      if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #row.recipes
          or type(recipe) ~= "string" or recipe == "" or seen[recipe] then
        fail("invalid admitted recipe")
      end
      recipes[index], seen[recipe], count = recipe, true, count + 1
    end
    if count ~= #row.recipes then fail("sparse admitted recipes") end
    out[name] = {recipes=recipes, effect_change=row.effect_change, configured_change=row.configured_change}
  end
  return out
end

return M
