local PACK = "electromagnetic-science-pack"
local TARGET = "recipe-prod-research_gears-1"
local CIRCULAR_RECIPE = "a-mir473-circular-electromagnetic-science"
local SEEDED_RECIPE = "z-mir473-seeded-electromagnetic-science"
local CIRCULAR_OWNER = "a-mir473-circular-electromagnetic-owner"
local SEEDED_OWNER = "z-mir473-seeded-electromagnetic-owner"
local FOREIGN = "mir473-named-science-foreign"
local PACKS = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "military-science-pack", "utility-science-pack",
  "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
  "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"
}

local function fail(message)
  error("[mir-named-science-replacement] " .. message)
end

local function dense(values, label)
  if type(values) ~= "table" then fail(label .. " is absent") end
  for index = 1, #values do
    if values[index] == nil then fail(label .. " is not dense") end
  end
end

local function item_amount(row, name, amount)
  return type(row) == "table" and (row.type == nil or row.type == "item")
    and (row.name or row[1]) == name and (row.amount or row[2]) == amount
end

local function exact_names(rows, expected, label)
  dense(rows, label)
  if #rows ~= #expected then fail(label .. " count differs") end
  local seen = {}
  for index, name in ipairs(expected) do
    if rows[index] ~= name or seen[rows[index]] then fail(label .. " differs") end
    seen[name] = true
  end
end

local function one_unlock(technology, recipe)
  local count = 0
  for _, effect in ipairs((technology or {}).effects or {}) do
    if effect.type == "unlock-recipe" and effect.recipe == recipe then count = count + 1 end
  end
  return count == 1
end

local function no_prerequisites(technology)
  return technology and (technology.prerequisites == nil
    or (type(technology.prerequisites) == "table" and next(technology.prerequisites) == nil))
end

local function producer_is_intact(name)
  local recipe = data.raw.recipe[name]
  if not recipe or recipe.enabled ~= false then return false end
  dense(recipe.ingredients, "fixture producer ingredients")
  dense(recipe.results, "fixture producer results")
  return #recipe.ingredients == 1 and item_amount(recipe.ingredients[1], "iron-plate", 1)
    and #recipe.results == 1 and item_amount(recipe.results[1], PACK, 1)
end

if data.raw.recipe[PACK] ~= nil then fail("canonical electromagnetic recipe was not removed during data-updates") end
if not producer_is_intact(CIRCULAR_RECIPE) or not producer_is_intact(SEEDED_RECIPE) then
  fail("fixture replacement producers changed")
end

local circular = data.raw.technology[CIRCULAR_OWNER]
local seeded = data.raw.technology[SEEDED_OWNER]
local foreign = data.raw.technology[FOREIGN]
if not circular or circular.enabled == false or not no_prerequisites(circular)
    or not circular.unit or #circular.unit.ingredients ~= 1
    or not item_amount(circular.unit.ingredients[1], PACK, 1)
    or not one_unlock(circular, CIRCULAR_RECIPE) then
  fail("circular source fixture changed")
end
if not seeded or seeded.enabled == false or not no_prerequisites(seeded)
    or seeded.unit ~= nil or type(seeded.research_trigger) ~= "table"
    or seeded.research_trigger.type ~= "craft-item" or seeded.research_trigger.item ~= "iron-plate"
    or seeded.research_trigger.count ~= 1 or not one_unlock(seeded, SEEDED_RECIPE) then
  fail("seeded source fixture changed")
end
if not foreign or foreign.enabled == false or #foreign.prerequisites ~= 1 or foreign.prerequisites[1] ~= PACK
    or not foreign.unit or foreign.unit.count ~= 2 or foreign.unit.time ~= 5
    or #foreign.unit.ingredients ~= 1 or not item_amount(foreign.unit.ingredients[1], PACK, 2)
    or #(foreign.effects or {}) ~= 0 then
  fail("foreign technology changed")
end

local target = data.raw.technology[TARGET]
if not target or target.enabled == false or not target.unit then fail("MIR gear research is not enabled") end
dense(target.unit.ingredients, "MIR gear ingredients")
if #target.unit.ingredients ~= #PACKS then fail("MIR gear ingredient count differs") end
for index, name in ipairs(PACKS) do
  if not item_amount(target.unit.ingredients[index], name, 1) then
    fail("MIR gear ingredient identity or amount differs")
  end
end

local expected_prerequisites = {}
for _, name in ipairs(PACKS) do
  expected_prerequisites[#expected_prerequisites + 1] = name == PACK and SEEDED_OWNER or name
end
exact_names(target.prerequisites, expected_prerequisites, "MIR gear prerequisites")
for _, prerequisite in ipairs(target.prerequisites) do
  if prerequisite == CIRCULAR_OWNER then fail("circular source became a MIR gear prerequisite") end
end

if type(log) == "function" then
  log("[MIR5_NAMED_SCIENCE_REPLACEMENT] target=" .. TARGET
    .. " seeded_owner=" .. SEEDED_OWNER .. " stage=data-final")
end
