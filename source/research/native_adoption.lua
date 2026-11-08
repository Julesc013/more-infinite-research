-- Additional recipes MIR appended or explicitly tuned on its five declared
-- native owners, explicit nonbinding settings and the selected finite worker
-- continuation cross this boundary.
-- Nonbinding decisions grant no new prototype mutation authority. This is not
-- saved history, an inferred owner list, or permission to accept extra effects.
local M = {prototype_name="more-infinite-research-native-adoptions"}

local NATIVE_FAMILIES = {
  ["low-density-structure-productivity"]="research_low_density_structure",
  ["plastic-bar-productivity"]="research_plastic",
  ["processing-unit-productivity"]="research_processing_unit",
  ["rocket-fuel-productivity"]="research_rocket_fuel",
  ["steel-plate-productivity"]="research_steel",
}

local function fail(message) error("MIR native adoption data: " .. message, 3) end
local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function M.prototype()
  return {type="mod-data", name=M.prototype_name, data={schema=1, owners={}, withheld={}, credits={}}}
end

-- The existing credit constructor validates only these five authored families
-- and their named current effects. Return plain detached transport groups;
-- neither a saved mask nor a force's contribution is inferred here.
function M.credit_groups(value)
  if value == nil then return {} end
  local out = {}
  for _, row in ipairs(require("research.native_credit_definitions").collected_descriptors(value)) do
    out[row.family] = out[row.family] or {}
    out[row.family][#out[row.family] + 1] = {recipe=row.recipe, change=row.change}
  end
  -- An explicitly empty family is still a complete current recipient set.
  -- Validation above has already restricted these keys and plain tables.
  for family in pairs(value) do out[family] = out[family] or {} end
  return out
end

local function withheld_rows(value, allowed)
  if value == nil then return {} end
  if type(value) ~= "table" then fail("invalid withheld native settings") end
  local out = {}
  for name, row in pairs(value) do
    if type(name) ~= "string" or type(row) ~= "table" or allowed[name] == nil
        or row.family ~= allowed[name] or type(row.generated) ~= "boolean" then
      fail("invalid withheld native owner")
    end
    for key in pairs(row) do
      if key ~= "family" and key ~= "generated" then fail("unknown withheld owner field") end
    end
    out[name] = {family=row.family, generated=row.generated}
  end
  return out
end

function M.plan(raw, targets, withheld, credits, worker_storage)
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
  local withheld_settings = withheld_rows(withheld, NATIVE_FAMILIES)
  local credit_groups = M.credit_groups(credits)
  local worker_route = worker_storage ~= nil
    and require("compatibility.worker_robot_storage").copy_route(worker_storage) or nil
  for name in pairs(withheld_settings) do
    if owners[name] ~= nil then fail("native owner is both adopted and withheld") end
  end
  if next(owners) == nil and next(withheld_settings) == nil and next(credit_groups) == nil
      and worker_route == nil then return nil end
  local prototype = raw["mod-data"] and raw["mod-data"][M.prototype_name]
  if type(prototype) ~= "table" or prototype.type ~= "mod-data" or prototype.name ~= M.prototype_name
      or type(prototype.data) ~= "table" or prototype.data.schema ~= 1
      or type(prototype.data.owners) ~= "table" or next(prototype.data.owners) ~= nil
      or prototype.data.withheld ~= nil and (type(prototype.data.withheld) ~= "table"
        or next(prototype.data.withheld) ~= nil)
      or prototype.data.credits ~= nil and (type(prototype.data.credits) ~= "table"
        or next(prototype.data.credits) ~= nil) then
    fail("missing or changed private prototype")
  end
  for key in pairs(prototype.data) do
    if key ~= "schema" and key ~= "owners" and key ~= "withheld" and key ~= "credits" then fail("changed private prototype data") end
  end
  return {prototype=prototype, owners=owners, withheld=withheld_settings, credits=credit_groups,
    worker_storage=worker_route}
end

function M.apply(patch)
  if patch then
    patch.prototype.data.owners = patch.owners
    patch.prototype.data.withheld = patch.withheld
    patch.prototype.data.credits = patch.credits
    patch.prototype.data.worker_storage = patch.worker_storage
    if patch.galore_sulfur_retired ~= nil then
      patch.prototype.data.galore_sulfur_retired = patch.galore_sulfur_retired
    end
  end
end

-- Called once by the control adapter with the one named LuaModData.data and
-- the authored native definitions. No force or recipe collection is inspected.
function M.read(value, definitions, admission_facts)
  if type(value) ~= "table" or value.schema ~= 1 or type(value.owners) ~= "table" then
    fail("invalid control data")
  end
  for key in pairs(value) do
    if key ~= "schema" and key ~= "owners" and key ~= "withheld" and key ~= "credits"
        and key ~= "galore_sulfur_retired" and key ~= "worker_storage" then fail("unknown control field") end
  end
  if value.galore_sulfur_retired ~= nil and type(value.galore_sulfur_retired) ~= "boolean" then
    fail("invalid named Galore retirement")
  end
  local allowed, out = {}, {}
  local families = {}
  for _, definition in ipairs(definitions) do
    allowed[definition.id], families[definition.id] = true, definition.family
  end
  local withheld = withheld_rows(value.withheld, families)
  for name, row in pairs(value.owners) do
    if allowed[name] ~= true or withheld[name] ~= nil or type(row) ~= "table" or not finite(row.effect_change)
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
  local credits = M.credit_groups(value.credits)
  local worker_storage = value.worker_storage ~= nil
    and require("compatibility.worker_robot_storage").copy_route(value.worker_storage) or nil
  if admission_facts ~= nil then
    admission_facts.galore_sulfur_retired = value.galore_sulfur_retired == true
    admission_facts.worker_storage = worker_storage
  end
  return out, withheld, credits
end

return M
